class RefreshAllCoversJob < ApplicationJob
  queue_as :default

  # Only one refresh all covers job at a time globally
  limits_concurrency to: 1, key: -> { "refresh_all_covers" }

  def perform
    refreshed = 0
    failed = 0

    Series.includes(:series_sources, :sources).find_each do |series|
      # Try to get cover from each source
      series.series_sources.each do |series_source|
        source = series_source.source
        next unless series_source.source_series_id.present?

        begin
          # Fetch fresh metadata from source to get cover_url
          adapter = adapter_for(source)
          series_result = adapter.series(series_source.source_series_id)

          if series_result.cover_url.present?
            # Update cover_url in database
            series.update!(cover_url: series_result.cover_url) if series.cover_url != series_result.cover_url

            # Download and attach cover
            download_cover(series, series_result.cover_url)
            refreshed += 1
            Rails.logger.info "RefreshAllCoversJob: Refreshed cover for #{series.canonical_title}"
            break # Got a cover, move to next series
          end
        rescue => e
          Rails.logger.warn "RefreshAllCoversJob: Failed to refresh cover for #{series.canonical_title} from #{source.key}: #{e.message}"
          failed += 1
        end
      end
    end

    Rails.logger.info "RefreshAllCoversJob: Completed - #{refreshed} refreshed, #{failed} failed"
  end

  private

  def adapter_for(source)
    Scrapers::AdapterRegistry.for(source)
  end

  def download_cover(series, cover_url)
    return if cover_url.blank?

    # Purge existing cover to force re-download
    series.cover.purge if series.cover.attached?

    CoverDownloader.download(series, cover_url)
  end
end
