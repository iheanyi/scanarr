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
    case source.key.to_s
    when "weeb_central"
      WeebCentral::Adapter.new(config: Rails.configuration.scraper_sources.fetch("weeb_central", {}))
    when "mangadex"
      Mangadex::Adapter.new(config: Rails.configuration.scraper_sources.fetch("mangadex", {}))
    else
      raise ArgumentError, "Unknown source key #{source.key.inspect}"
    end
  end

  def download_cover(series, cover_url)
    return if cover_url.blank?

    # Purge existing cover to force re-download
    series.cover.purge if series.cover.attached?

    uri = URI.parse(cover_url)
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 10
      http.read_timeout = 30
    end

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    return unless response.is_a?(Net::HTTPSuccess)

    content_type = response["content-type"]
    extension = case content_type
                when /jpeg|jpg/i then "jpg"
                when /png/i then "png"
                when /webp/i then "webp"
                when /gif/i then "gif"
                else "jpg"
                end

    series.cover.attach(
      io: StringIO.new(response.body),
      filename: "cover.#{extension}",
      content_type: content_type
    )
  rescue OpenSSL::SSL::SSLError => e
    Rails.logger.warn "SSL error downloading cover for #{series.canonical_title}, retrying insecure: #{e.message}"
    retry_download_cover_insecure(series, cover_url)
  rescue => e
    Rails.logger.warn "Failed to download cover for #{series.canonical_title}: #{e.message}"
  end

  def retry_download_cover_insecure(series, cover_url)
    uri = URI.parse(cover_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    return unless response.is_a?(Net::HTTPSuccess)

    content_type = response["content-type"]
    extension = case content_type
                when /jpeg|jpg/i then "jpg"
                when /png/i then "png"
                when /webp/i then "webp"
                when /gif/i then "gif"
                else "jpg"
                end

    series.cover.attach(
      io: StringIO.new(response.body),
      filename: "cover.#{extension}",
      content_type: content_type
    )
  rescue => e
    Rails.logger.warn "Failed to download cover (insecure retry) for #{series.canonical_title}: #{e.message}"
  end
end
