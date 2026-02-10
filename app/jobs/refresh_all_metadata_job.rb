class RefreshAllMetadataJob < ApplicationJob
  queue_as :default

  # Only one refresh all metadata job at a time globally
  limits_concurrency to: 1, key: -> { "refresh_all_metadata" }

  def perform
    refreshed = 0
    failed = 0
    skipped = 0

    Series.includes(:series_sources, :sources).find_each do |series|
      series.series_sources.each do |series_source|
        source = series_source.source
        next unless series_source.source_series_id.present?

        unless Scrapers::AdapterRegistry.registered?(source.key)
          skipped += 1
          next
        end

        begin
          adapter = Scrapers::AdapterRegistry.for(source)
          importer = SeriesImporter.new(source: source, adapter: adapter)
          importer.import!(series_source.source_series_id)
          refreshed += 1
          Rails.logger.info "RefreshAllMetadataJob: Refreshed #{series.canonical_title} from #{source.key}"
          break # One successful source is enough per series
        rescue => e
          Rails.logger.warn "RefreshAllMetadataJob: Failed to refresh #{series.canonical_title} from #{source.key}: #{e.message}"
          failed += 1
        end
      end
    end

    Rails.logger.info "RefreshAllMetadataJob: Completed - #{refreshed} refreshed, #{failed} failed, #{skipped} skipped"
  end
end
