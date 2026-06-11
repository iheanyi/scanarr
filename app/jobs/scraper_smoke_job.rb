class ScraperSmokeJob < ApplicationJob
  queue_as :default

  # Only one smoke test per source at a time
  limits_concurrency to: 1, key: ->(run_id) {
    run = ScraperRun.find_by(id: run_id)
    "smoke_test:#{run&.source_id || 'unknown'}"
  }

  def perform(run_id)
    run = ScraperRun.find_by(id: run_id)
    unless run
      Rails.logger.info "ScraperSmokeJob: ScraperRun #{run_id} no longer exists, skipping"
      return
    end
    source = run.source
    adapter = adapter_for(source)

    results = adapter.search("one piece")
    series = results.first && adapter.series(results.first.url)
    chapters = series ? adapter.chapters(series.url) : []
    pages = chapters.first ? adapter.pages(chapters.first.url) : []

    run.update!(
      status: "success",
      finished_at: Time.current,
      stats_json: {
        query: "one piece",
        search_count: results.size,
        series_url: series&.url,
        chapter_count: chapters.size,
        page_count: pages.size
      }
    )
    Sources::HealthEvaluator.new(source).call
  rescue StandardError => error
    run&.update!(
      status: "failed",
      finished_at: Time.current,
      error: "#{error.class}: #{error.message}"
    )
    Sources::HealthEvaluator.new(source).call if source
    raise
  end

  private

  def adapter_for(source)
    Scrapers::AdapterRegistry.for(source)
  end
end
