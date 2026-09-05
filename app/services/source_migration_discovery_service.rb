require "timeout"

class SourceMigrationDiscoveryService
  Result = Data.define(:candidates, :errors)
  Candidate = Data.define(:source, :result, :chapter_count, :confidence, :linked)
  WorkerResult = Data.define(:candidates, :error)

  SEARCH_TIMEOUT_SECONDS = 8
  DISCOVERY_TIMEOUT_SECONDS = SEARCH_TIMEOUT_SECONDS + 2
  MAX_WORKERS = 4
  MIN_CONFIDENCE = 0.45

  def initialize(series:, from_source:, source_id: nil)
    @series = series
    @from_source = from_source
    @source_id = source_id
    @linked_series_ids = @series.series_sources.pluck(:source_id, :source_series_id).to_h
  end

  def call
    # Candidate targets exclude broken/dead sources: suggesting a migration
    # onto a source that cannot serve chapters helps nobody, and each one
    # would eat the full search timeout. The from_source may itself be broken
    # or dead; discovery never makes a request to it.
    sources = Source.where(enabled: true)
      .where.not(health_status: %w[broken dead])
      .where.not(id: @from_source.id)
      .order(:name)
    sources = sources.where(id: @source_id) if @source_id.present?
    sources = sources.to_a
    if @source_id.present? && sources.empty?
      return Result.new(candidates: [], errors: [ "This source is no longer available for replacement. Refresh to see available sources." ])
    end

    discovery = discover_candidates(sources)
    Result.new(candidates: sort_candidates(discovery[:candidates]), errors: discovery[:errors])
  end

  private

  def discover_candidates(sources)
    return { candidates: [], errors: [] } if sources.empty?
    if sources.one?
      # The interactive flow checks one provider. Stay in the Rails request
      # executor so adapter autoloading does not contend with a waiting thread.
      result = discover_source_candidate(sources.first)
      return { candidates: result.candidates, errors: [ result.error ].compact }
    end

    executor = Concurrent::FixedThreadPool.new([ MAX_WORKERS, sources.size ].min)
    candidates = []
    errors = []
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DISCOVERY_TIMEOUT_SECONDS
    begin
      futures = sources.map do |source|
        Concurrent::Promises.future_on(executor, source) do |candidate_source|
          discover_source_candidate(candidate_source)
        end
      end

      futures.each_with_index do |future, index|
        source = sources[index]
        remaining = [ deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0 ].max
        worker_result = future.value!(remaining)
        if worker_result.nil?
          errors << "#{source.name}: discovery timed out; try searching this source on its own"
          next
        end

        unless worker_result.is_a?(WorkerResult)
          errors << "#{source.name}: unexpected empty result"
          next
        end

        candidates.concat(worker_result.candidates)
        errors << worker_result.error if worker_result.error.present?
      rescue StandardError => e
        errors << "#{source.name}: #{e.message.truncate(100)}"
      end
    ensure
      executor.kill
      executor.wait_for_termination(1)
    end

    { candidates:, errors: }
  end

  def discover_source_candidate(source)
    unless Scrapers::AdapterRegistry.registered?(source.key)
      return WorkerResult.new(candidates: [], error: "#{source.name}: adapter not implemented")
    end

    matches = Timeout.timeout(SEARCH_TIMEOUT_SECONDS) do
      adapter = Scrapers::AdapterRegistry.for(source)
      if @linked_series_ids[source.id].present?
        [ linked_match_for(adapter, @linked_series_ids.fetch(source.id)) ]
      else
        matches_for(adapter.search(@series.canonical_title))
      end
    end
    candidates = matches.map do |result, confidence|
      # Fetch chapter details only after the reader chooses an edition.
      chapter_count = search_chapter_count(result)
      Candidate.new(
        source: source,
        result: result,
        chapter_count: chapter_count,
        confidence: confidence,
        linked: @linked_series_ids[source.id].present?
      )
    end
    WorkerResult.new(candidates: candidates, error: nil)
  rescue Timeout::Error
    WorkerResult.new(candidates: [], error: "#{source.name}: search timed out after #{SEARCH_TIMEOUT_SECONDS}s")
  rescue Scrapers::Errors::RateLimitError
    WorkerResult.new(candidates: [], error: "#{source.name}: rate limited; try again later")
  rescue Scrapers::Errors::SourceUnavailableError => e
    WorkerResult.new(candidates: [], error: "#{source.name}: #{e.message.truncate(100)}")
  rescue StandardError => e
    WorkerResult.new(candidates: [], error: "#{source.name}: #{e.message.truncate(100)}")
  end

  def linked_match_for(adapter, source_series_id)
    linked_series = adapter.series(source_series_id)
    result = ResultTypes::SearchResult.new(
      id: source_series_id,
      title: linked_series.title,
      url: linked_series.url,
      cover_url: linked_series.cover_url
    )
    [ result, Sources::TitleMatcher.score(@series.canonical_title, linked_series.title) ]
  end

  def matches_for(results)
    results.filter_map do |result|
      next if result.id.blank? || result.url.blank?

      confidence = Sources::TitleMatcher.score(@series.canonical_title, result.title)
      [ result, confidence ] if confidence >= MIN_CONFIDENCE
    end.sort_by { |(_, confidence)| -confidence }
      .uniq { |(result, _)| result.id.to_s }
  end

  def search_chapter_count(result)
    result.chapter_count.to_i if result.respond_to?(:chapter_count) && result.chapter_count.present?
  end

  def sort_candidates(candidates)
    candidates.sort_by do |candidate|
      [ -candidate.confidence, candidate.chapter_count.nil? ? 1 : 0, -(candidate.chapter_count || 0), candidate.source.name.to_s.downcase ]
    end
  end
end
