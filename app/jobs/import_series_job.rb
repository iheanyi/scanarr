class ImportSeriesJob < ApplicationJob
  queue_as :default

  # Limit imports per source to respect rate limits (3 concurrent per source)
  # Also prevent duplicate imports of the same series URL
  limits_concurrency to: 1, key: ->(run_id, series_url) { "import_series:#{series_url}" }

  def perform(run_id, series_url)
    run = ScraperRun.find_by(id: run_id)
    unless run
      Rails.logger.info "ImportSeriesJob: ScraperRun #{run_id} no longer exists, skipping"
      return
    end
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
    AdapterRegistry.for(source)
  end
end
