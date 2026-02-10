require "timeout"

class SourceMigrationDiscoveryService
  Result = Data.define(:candidates, :errors)
  Candidate = Data.define(:source, :result, :chapter_count, :confidence, :linked)

  SEARCH_TIMEOUT_SECONDS = 8
  CHAPTER_COUNT_TIMEOUT_SECONDS = 12
  MAX_WORKERS = 4
  MIN_CONFIDENCE = 0.45

  def initialize(series:, from_source:)
    @series = series
    @from_source = from_source
    @errors = []
    @linked_source_ids = @series.sources.pluck(:id)
  end

  def call
    sources = Source.where(enabled: true).where.not(id: @from_source.id).order(:name).to_a
    candidates = discover_candidates(sources)
    Result.new(candidates: sort_candidates(candidates), errors: @errors)
  end

  private

  def discover_candidates(sources)
    return [] if sources.empty?

    executor = Concurrent::FixedThreadPool.new([ MAX_WORKERS, sources.size ].min)
    begin
      futures = sources.map do |source|
        Concurrent::Promises.future_on(executor, source) do |candidate_source|
          discover_source_candidate(candidate_source)
        end
      end

      futures.filter_map.with_index do |future, index|
        source = sources[index]
        future.value!(SEARCH_TIMEOUT_SECONDS)
      rescue Concurrent::TimeoutError
        @errors << "#{source.name}: search timed out"
        nil
      rescue StandardError => e
        @errors << "#{source.name}: #{e.message.truncate(100)}"
        nil
      end
    ensure
      executor.shutdown
      executor.wait_for_termination(1)
    end
  end

  def discover_source_candidate(source)
    unless Scrapers::AdapterRegistry.registered?(source.key)
      @errors << "#{source.name}: adapter not implemented"
      return nil
    end

    adapter = Scrapers::AdapterRegistry.for(source)
    results = adapter.search(@series.canonical_title).first(5)
    best_match, confidence = best_match_for(results)
    return nil if best_match.nil?

    chapter_count = chapter_count_for(adapter, best_match)

    Candidate.new(
      source: source,
      result: best_match,
      chapter_count: chapter_count,
      confidence: confidence,
      linked: @linked_source_ids.include?(source.id)
    )
  rescue StandardError => e
    @errors << "#{source.name}: #{e.message.truncate(100)}"
    nil
  end

  def best_match_for(results)
    scored = results.filter_map do |result|
      confidence = score_result(result)
      next if confidence < MIN_CONFIDENCE

      [ result, confidence ]
    end

    scored.max_by { |(_, confidence)| confidence } || [ nil, 0.0 ]
  end

  def score_result(result)
    series_title = normalize(@series.canonical_title)
    result_title = normalize(result.title)
    return 0.0 if series_title.blank? || result_title.blank?
    return 1.0 if result_title == series_title
    return 0.8 if result_title.include?(series_title) || series_title.include?(result_title)

    shared_terms = (series_title.split & result_title.split).size
    largest_term_count = [ series_title.split.size, result_title.split.size ].max
    return 0.0 if largest_term_count.zero?

    (shared_terms.to_f / largest_term_count).round(2)
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

  def normalize(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end
end
