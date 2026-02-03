class ImportSeriesJob < ApplicationJob
  queue_as :default

  # Limit imports per source to respect rate limits (3 concurrent per source)
  # Also prevent duplicate imports of the same series URL
  limits_concurrency to: 1, key: ->(run_id, series_url) { "import_series:#{series_url}" }

  def perform(run_id, series_url)
    run = ScraperRun.find(run_id)
    source = run.source

    importer = SeriesImporter.new(source: source, adapter: adapter_for(source))
    series = importer.import!(series_url)
    chapter_count = series.chapters.where(source: source).count

    run.update!(
      status: "success",
      finished_at: Time.current,
      stats_json: {
        series_id: series.id,
        series_title: series.canonical_title,
        series_url: series_url,
        chapter_count: chapter_count
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
