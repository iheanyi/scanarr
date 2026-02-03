class DownloadChapterJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :default

  # Limit concurrent downloads per source to avoid overloading
  # Key format: "download_chapter:weeb_central" or "download_chapter:mangadex"
  limits_concurrency to: 3, key: ->(chapter_url, **kwargs) { "download_chapter:#{kwargs[:source_key] || 'weeb_central'}" }

  def perform(
    chapter_url,
    source_key: "weeb_central",
    series_title:,
    source_series_id: nil,
    chapter_number:,
    chapter_title: nil,
    language: nil,
    group: nil,
    max_pages: nil,
    release_id: nil,
    adapter: nil,
    http: nil
  )
    # These are set once and persist across resumptions
    @chapter_url = chapter_url
    @source_key = source_key
    @series_title = series_title
    @source_series_id = source_series_id
    @chapter_number = chapter_number
    @chapter_title = chapter_title
    @language = language
    @group = group
    @max_pages = max_pages
    @release_id = release_id
    @adapter = adapter
    @http = http

    step :setup_download do
      setup_entities
    end

    step :fetch_page_urls do
      fetch_pages
    end

    step(:download_pages, start: 0) do |s|
      download_pages_with_cursor(s)
    end

    step :finalize_download do
      finalize
    end

    # Return the release for callers that expect it
    @release
  end

  private

  def current_adapter
    @adapter ||= adapter_for(@source_key)
  end

  def current_http
    @http ||= HttpClient.new(config: current_adapter.config)
  end

  def response_success?(response)
    # Handle both Net::HTTPResponse (has .code) and test fake responses (have .status)
    if response.respond_to?(:code)
      response.code.to_i == 200
    elsif response.respond_to?(:status)
      response.status == 200
    else
      false
    end
  end

  def response_body(response)
    response.body
  end

  def response_content_type(response)
    # Handle different response types
    if response.respond_to?(:headers) && response.headers.is_a?(Hash)
      response.headers["content-type"] || "image/jpeg"
    elsif response.respond_to?(:[]) && !response.is_a?(Struct)
      response["content-type"] || "image/jpeg"
    else
      "image/jpeg"
    end
  end

  def setup_entities
    @source = Source.find_or_create_by!(key: @source_key) do |record|
      record.name = @source_key.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
      record.base_url = current_adapter.config["base_url"]
    end

    if @release_id.present?
      @release = Release.find_by(id: @release_id)
      unless @release
        Rails.logger.info "DownloadChapterJob: Release #{@release_id} no longer exists, skipping"
        return # Release was deleted, nothing to do
      end
      @chapter = @release.chapter
      @series = @chapter.series
    else
      @series = find_or_create_series(source: @source, series_title: @series_title, source_series_id: @source_series_id)

      @chapter = Chapter.find_or_create_by!(
        series: @series,
        chapter_number: @chapter_number,
        language: @language,
        group: @group
      ) do |record|
        record.title = @chapter_title
        record.source = @source
      end
      if @chapter_title && @chapter.title != @chapter_title
        @chapter.update!(title: @chapter_title)
      end

      @release = @chapter.releases.create!(
        source: @source,
        format: "pages",
        source_url: @chapter_url
      )
    end

    series_source = SeriesSource.find_by(series: @series, source: @source)
    series_source ||= SeriesSource.create!(series: @series, source: @source)

    builder = LibraryPathBuilder.new(series: @series, source: @source)
    base_path = builder.base_path
    if base_path.present? && series_source.library_base_path != base_path
      series_source.update!(library_base_path: base_path)
    end

    @file_asset = @release.file_asset
    if @file_asset
      # Resume from existing state - don't reset if already downloading
      unless @file_asset.download_status == "downloading"
        @file_asset.update!(
          download_status: "downloading",
          download_error: nil,
          path: @file_asset.path.presence || builder.chapter_path(@chapter)
        )
      end
    else
      @file_asset = @release.create_file_asset!(
        format: "pages",
        download_status: "downloading",
        pages_downloaded: 0,
        download_error: nil,
        path: builder.chapter_path(@chapter)
      )
    end

    broadcast_chapter_update(@chapter, @source)
  end

  def fetch_pages
    @pages = current_adapter.pages(@chapter_url)
    @file_asset.update!(pages_expected: @pages.size)
    broadcast_chapter_update(@chapter, @source)
  end

  def download_pages_with_cursor(step)
    # Resume from cursor (page index we left off at)
    start_idx = step.cursor || 0

    # Reload to get fresh page data if resuming
    @pages ||= current_adapter.pages(@chapter_url)

    @pages[start_idx..].each_with_index do |page_data, relative_idx|
      idx = start_idx + relative_idx
      position = idx + 1

      # Skip if this page already exists (idempotent)
      existing_page = @file_asset.pages.find_by(position: position)
      if existing_page&.image&.attached?
        next # Already downloaded
      end

      # Get the URL from the page data (handles both Page struct and string)
      page_url = page_data.respond_to?(:url) ? page_data.url : page_data.to_s

      # Download the page
      response = current_http.get(page_url)
      unless response_success?(response)
        Rails.logger.warn "DownloadChapterJob: Failed to download page #{position} from #{page_url}"
        next
      end

      content_type = response_content_type(response)
      extension = case content_type
                  when /png/i then "png"
                  when /webp/i then "webp"
                  when /gif/i then "gif"
                  else "jpg"
                  end

      # Use find_or_create_by! to handle race conditions
      page = existing_page || @file_asset.pages.find_or_create_by!(position: position)
      page.image.attach(
        io: StringIO.new(response.body),
        filename: "#{position.to_s.rjust(3, '0')}.#{extension}",
        content_type: content_type
      )

      @file_asset.update!(pages_downloaded: position)

      # Broadcast progress every 5 pages
      broadcast_chapter_update(@chapter, @source) if (position % 5).zero?

      # Checkpoint after each page - allows job to be interrupted and resumed
      step.advance! from: position
    end
  end

  def finalize
    @file_asset.update!(
      page_count: @file_asset.pages.count,
      download_status: "complete",
      pages_downloaded: @file_asset.pages.count
    )
    @file_asset.archive.purge if @file_asset.archive.attached?
    ChapterPackager.new(@file_asset).package!

    broadcast_chapter_update(@chapter, @source)
  end

  rescue_from(StandardError) do |error|
    @file_asset&.update!(download_status: "failed", download_error: "#{error.class}: #{error.message}")
    broadcast_chapter_update(@chapter, @source) if @chapter
    broadcast_admin_download_update
    raise
  end

  private

  def broadcast_chapter_update(chapter, source)
    series = chapter.series
    # Broadcast to series page
    Turbo::StreamsChannel.broadcast_replace_to(
      [series, :downloads],
      target: ActionView::RecordIdentifier.dom_id(chapter),
      partial: "series/chapter_row",
      locals: { chapter: chapter.reload, source: source, series: series, progress: nil }
    )

    # Broadcast to admin downloads page
    broadcast_admin_download_update
  rescue StandardError => e
    Rails.logger.warn "Failed to broadcast chapter update: #{e.message}"
  end

  def broadcast_admin_download_update
    return unless @file_asset

    Turbo::StreamsChannel.broadcast_replace_to(
      "admin_downloads",
      target: ActionView::RecordIdentifier.dom_id(@file_asset),
      partial: "admin/downloads/download_row",
      locals: { download: @file_asset.reload }
    )
  rescue StandardError => e
    Rails.logger.warn "Failed to broadcast admin download update: #{e.message}"
  end

  def adapter_for(source_key)
    case source_key.to_s
    when "weeb_central"
      WeebCentral::Adapter.new(config: Rails.configuration.scraper_sources.fetch("weeb_central", {}))
    when "mangadex"
      Mangadex::Adapter.new(config: Rails.configuration.scraper_sources.fetch("mangadex", {}))
    else
      raise ArgumentError, "Unknown source_key #{source_key.inspect}"
    end
  end

  def find_or_create_series(source:, series_title:, source_series_id:)
    if source_series_id.present?
      series_source = SeriesSource.find_by(source: source, source_series_id: source_series_id)
      return series_source.series if series_source
    end

    series_source = SeriesSource.joins(:series)
                                .where(source: source, series: { canonical_title: series_title })
                                .first
    if series_source
      if source_series_id.present? && series_source.source_series_id != source_series_id
        series_source.update!(source_series_id: source_series_id)
      end
      return series_source.series
    end

    series = Series.create!(canonical_title: series_title)
    SeriesSource.create!(series: series, source: source, source_series_id: source_series_id)
    series
  end
end
