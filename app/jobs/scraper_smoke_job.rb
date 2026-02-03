class ScraperSmokeJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = ScraperRun.find(run_id)
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
  rescue StandardError => error
    run&.update!(
      status: "failed",
      finished_at: Time.current,
      error: "#{error.class}: #{error.message}"
    )
    raise
  end

  private

  def adapter_for(source)
    case source.key.to_s
    when "weeb_central"
      WeebCentral::Adapter.new(config: Rails.configuration.scraper_sources.fetch("weeb_central", {}))
    when "mangadex"
      Mangadex::Adapter.new(config: Rails.configuration.scraper_sources.fetch("mangadex", {}))
    else
      raise ArgumentError, "Unknown source key #{source.key.inspect}"
    end
  end
end
