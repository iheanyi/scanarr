class SearchController < ApplicationController
  SEARCH_TIMEOUT_SECONDS = 8
  MAX_SEARCH_WORKERS = 6

  def index
    @sources = Source.where(enabled: true).order(:name, :key)
    @query = params[:q].to_s.strip
    @selected_source_ids = params[:sources].present? ? Array(params[:sources]) : @sources.pluck(:id).map(&:to_s)

    @results = []
    @errors = []
    return if @query.blank?

    selected_sources = @sources.where(id: @selected_source_ids).to_a
    search_sources(selected_sources)
    sort_results_by_chapter_count!
  end

  private

  def search_sources(sources)
    return if sources.empty?

    worker_count = [ sources.size, MAX_SEARCH_WORKERS ].min
    executor = Concurrent::FixedThreadPool.new(worker_count)
    futures = []
    begin
      futures = sources.map do |source|
        Concurrent::Promises.future_on(executor, source) do |target_source|
          search_source(target_source)
        end
      end

      futures.each_with_index do |future, index|
        source = sources[index]
        payload = future.value!(SEARCH_TIMEOUT_SECONDS)
        if payload.nil?
          @errors << { source: source, message: "Search timed out" }
          Rails.logger.warn "Search timed out for #{source.key}"
          next
        end

        @results.concat(payload[:results])
        @errors << payload[:error] if payload[:error]
      rescue StandardError => e
        @errors << { source: source, message: e.message.truncate(100) }
        Rails.logger.warn "Search failed for #{source.key}: #{e.class} - #{e.message}"
      end
    ensure
      executor.shutdown
      executor.wait_for_termination(1)
    end
  end

  def search_source(source)
    unless Scrapers::AdapterRegistry.registered?(source.key)
      return { results: [], error: { source: source, message: "Adapter not implemented" } }
    end

    adapter = Scrapers::AdapterRegistry.for(source)
    results = adapter.search(@query).map do |result|
      { source: source, result: result }
    end
    { results: results, error: nil }
  rescue Scrapers::AdapterRegistry::UnknownSourceError => e
    Rails.logger.warn "Search skipped for #{source.key}: #{e.message}"
    { results: [], error: { source: source, message: "Source not configured" } }
  rescue StandardError => e
    Rails.logger.warn "Search failed for #{source.key}: #{e.class} - #{e.message}"
    { results: [], error: { source: source, message: e.message.truncate(100) } }
  end

  def sort_results_by_chapter_count!
    @results.sort_by! do |item|
      chapter_count = item[:result].respond_to?(:chapter_count) ? item[:result].chapter_count : nil
      [ chapter_count.nil? ? 1 : 0, -(chapter_count || 0), item[:result].title.to_s.downcase ]
    end
  end

  def source_slug(source)
    source.slug
  end
  helper_method :source_slug
end
