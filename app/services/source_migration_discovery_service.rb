require "timeout"

class SourceMigrationDiscoveryService
  Result = Data.define(:candidates, :errors)
  Candidate = Data.define(:source, :result, :chapter_count, :confidence, :linked)
  WorkerResult = Data.define(:candidate, :error)

  SEARCH_TIMEOUT_SECONDS = 8
  CHAPTER_COUNT_TIMEOUT_SECONDS = 12
  WORKER_WAIT_TIMEOUT_SECONDS = SEARCH_TIMEOUT_SECONDS + 2
  MAX_WORKERS = 4
  MIN_CONFIDENCE = 0.45

  def initialize(series:, from_source:)
    @series = series
    @from_source = from_source
    @linked_source_ids = @series.sources.pluck(:id)
  end

  def call
    sources = Source.where(enabled: true).where.not(id: @from_source.id).order(:name).to_a
    discovery = discover_candidates(sources)
    Result.new(candidates: sort_candidates(discovery[:candidates]), errors: discovery[:errors])
  end

  private

  def discover_candidates(sources)
    return { candidates: [], errors: [] } if sources.empty?

    executor = Concurrent::FixedThreadPool.new([ MAX_WORKERS, sources.size ].min)
    candidates = []
    errors = []
    begin
      futures = sources.map do |source|
        Concurrent::Promises.future_on(executor, source) do |candidate_source|
          discover_source_candidate(candidate_source)
        end
      end

      futures.each_with_index do |future, index|
        source = sources[index]
        worker_result = future.value!(WORKER_WAIT_TIMEOUT_SECONDS)
        if worker_result.nil?
          errors << "#{source.name}: search timed out after #{SEARCH_TIMEOUT_SECONDS}s"
          next
        end

        unless worker_result.is_a?(WorkerResult)
          errors << "#{source.name}: unexpected empty result"
          next
        end

        candidates << worker_result.candidate if worker_result.candidate.present?
        errors << worker_result.error if worker_result.error.present?
      rescue StandardError => e
        errors << "#{source.name}: #{e.message.truncate(100)}"
      end
    ensure
      executor.shutdown
      executor.wait_for_termination(1)
    end

    { candidates:, errors: }
  end

  def discover_source_candidate(source)
    unless Scrapers::AdapterRegistry.registered?(source.key)
      return WorkerResult.new(candidate: nil, error: "#{source.name}: adapter not implemented")
    end

    adapter = Scrapers::AdapterRegistry.for(source)
    results = Timeout.timeout(SEARCH_TIMEOUT_SECONDS) do
      adapter.search(@series.canonical_title).first(5)
    end
    best_match, confidence = best_match_for(results)
    return WorkerResult.new(candidate: nil, error: nil) if best_match.nil?

    chapter_count = chapter_count_for(adapter, best_match)

    WorkerResult.new(
      candidate: Candidate.new(
        source: source,
        result: best_match,
        chapter_count: chapter_count,
        confidence: confidence,
        linked: @linked_source_ids.include?(source.id)
      ),
      error: nil
    )
  rescue Timeout::Error
    WorkerResult.new(candidate: nil, error: "#{source.name}: search timed out after #{SEARCH_TIMEOUT_SECONDS}s")
  rescue Scrapers::Errors::RateLimitError
    WorkerResult.new(candidate: nil, error: "#{source.name}: blocked by anti-bot protection")
  rescue Scrapers::Errors::SourceUnavailableError => e
    WorkerResult.new(candidate: nil, error: "#{source.name}: #{e.message.truncate(100)}")
  rescue StandardError => e
    WorkerResult.new(candidate: nil, error: "#{source.name}: #{e.message.truncate(100)}")
  end

  def best_match_for(results)
    Sources::TitleMatcher.best_match(@series.canonical_title, results, min_confidence: MIN_CONFIDENCE)
  end

  def chapter_count_for(adapter, result)
    if result.respond_to?(:chapter_count) && result.chapter_count.present?
      return result.chapter_count.to_i
    end

    Timeout.timeout(CHAPTER_COUNT_TIMEOUT_SECONDS) do
      adapter.chapters(result.url).size
    end
  rescue StandardError
    nil
  end

  def sort_candidates(candidates)
    candidates.sort_by do |candidate|
      [ candidate.chapter_count.nil? ? 1 : 0, -(candidate.chapter_count || 0), -candidate.confidence, candidate.source.name.to_s.downcase ]
    end
  end
end
