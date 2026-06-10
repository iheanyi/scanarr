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
    @skip_download = false

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
        @skip_download = true
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
        record.source_url = @chapter_url
      end

      # Update existing chapter with title/source_url if not already set
      updates = {}
      updates[:title] = @chapter_title if @chapter_title && @chapter.title != @chapter_title
      updates[:source_url] = @chapter_url if @chapter_url.present? && @chapter.source_url.blank?
      @chapter.update!(updates) if updates.any?

      @release = @chapter.releases.find_or_create_by!(source: @source) do |r|
        r.format = "pages"
        r.source_url = @chapter_url
      end

      # Update source_url if it changed
      @release.update!(source_url: @chapter_url) if @release.source_url != @chapter_url
    end

    series_source = SeriesSource.find_by(series: @series, source: @source)
    series_source ||= SeriesSource.create!(series: @series, source: @source)

    base_path = library_path_builder.base_path
    if base_path.present? && series_source.library_base_path != base_path
      series_source.update!(library_base_path: base_path)
    end

    @file_asset = @release.file_asset
    if @file_asset
      # Clean up old pages when re-downloading
      unless @file_asset.download_status == "downloading"
        semantic_path = library_path_builder.chapter_path(@chapter)

        @file_asset.archive.purge if @file_asset.archive.attached?
        # Purge old page blobs to avoid orphans
        @file_asset.pages.includes(image_attachment: :blob).each do |page|
          page.image.purge if page.image.attached?
        end
        @file_asset.pages.destroy_all

        @file_asset.update!(
          download_status: "downloading",
          download_error: nil,
          pages_downloaded: 0,
          pages_expected: nil,
          path: semantic_path.presence || @file_asset.path
        )
      end
    else
      @file_asset = @release.create_file_asset!(
        format: "pages",
        download_status: "downloading",
        pages_downloaded: 0,
        download_error: nil,
        path: library_path_builder.chapter_path(@chapter)
      )
    end

    # Broadcast status change (queued -> downloading)
    broadcast_chapter_update(@chapter, @source)
    broadcast_admin_download_update
  end

  def fetch_pages
    ensure_runtime_entities!
    return if skip_download?
    return if stop_if_cancelled!

    @pages = current_adapter.pages(@chapter_url)
    @file_asset.update!(pages_expected: @pages.size)
    broadcast_chapter_update(@chapter, @source)
  end

  def download_pages_with_cursor(step)
    ensure_runtime_entities!
    return if skip_download?
    return if stop_if_cancelled!

    # Resume from cursor (page index we left off at)
    start_idx = step.cursor || 0

    # Reload to get fresh page data if resuming
    @pages ||= current_adapter.pages(@chapter_url)

    @pages[start_idx..].each_with_index do |page_data, relative_idx|
      idx = start_idx + relative_idx
      position = idx + 1
      return if stop_if_cancelled!

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
      attach_options = {
        io: StringIO.new(response.body),
        filename: "#{position.to_s.rjust(3, '0')}.#{extension}",
        content_type: content_type
      }
      key = library_path_builder.page_path(@chapter, position: position, extension: extension)
      attach_options[:key] = key if key.present?

      page.image.attach(attach_options)

      # Pre-process the WebP display variant so it's ready before the user opens the chapter
      page.preprocess_display_variant!

      @file_asset.update!(pages_downloaded: position)

      # Broadcast progress updates every 5 pages to reduce rendering overhead
      # Each broadcast renders a full partial, so less frequent = less CPU in the job
      if (position % 5).zero? || position == @pages.size
        broadcast_admin_download_update
        broadcast_chapter_update(@chapter, @source)
      end

      # Checkpoint after each page - allows job to be interrupted and resumed
      step.advance! from: position
    end
  end

  def finalize
    ensure_runtime_entities!
    return if skip_download?
    return if stop_if_cancelled!

    pages = @file_asset.pages.includes(image_attachment: :blob).order(:position)
    page_count = pages.count

    # Verify blobs actually exist on disk before marking complete
    # (page.image.attached? only checks the DB association, not the actual file)
    sample_pages = [ pages.first, pages.last ].compact.uniq
    missing = sample_pages.any? { |p| p.image.blob && !ActiveStorage::Blob.service.exist?(p.image.blob.key) }

    if missing
      @file_asset.update!(
        page_count: page_count,
        download_status: "failed",
        pages_downloaded: @file_asset.pages_downloaded,
        download_error: "Download verification failed: blob files missing from storage"
      )
      Rails.logger.error "DownloadChapterJob: Blob verification failed for file_asset #{@file_asset.id}"
      broadcast_chapter_update(@chapter, @source)
      return
    end

    @file_asset.update!(
      page_count: page_count,
      download_status: "complete",
      pages_downloaded: page_count
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
    chapter.reload
    latest_release = chapter.releases.includes(:file_asset).order(created_at: :desc).first
    # Broadcast to series page
    Turbo::StreamsChannel.broadcast_replace_to(
      [ series, :downloads ],
      target: ActionView::RecordIdentifier.dom_id(chapter),
      partial: "series/chapter_row",
      locals: { chapter: chapter, source: source, series: series, progress: nil, latest_release: latest_release }
    )

    # Broadcast to admin downloads page
    broadcast_admin_download_update
  rescue StandardError => e
    Rails.logger.warn "Failed to broadcast chapter update: #{e.message}"
  end

  def broadcast_admin_download_update
    return unless @file_asset

    file_asset = @file_asset.reload
    target_id = ActionView::RecordIdentifier.dom_id(file_asset)

    # Broadcast update - uses "refresh" action which will:
    # - Replace if element exists
    # - Be ignored if element doesn't exist (user will see it on next page load)
    Turbo::StreamsChannel.broadcast_replace_to(
      "admin_downloads",
      target: target_id,
      partial: "admin/downloads/download_row",
      locals: { download: file_asset }
    )
  rescue StandardError => e
    Rails.logger.warn "Failed to broadcast admin download update: #{e.message}"
  end

  def adapter_for(source_key)
    Scrapers::AdapterRegistry.for(source_key.to_s)
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

  # ActiveJob::Continuable persists step cursors, but not arbitrary runtime ivars.
  # On resume/retry, later steps can run with nil @file_asset/@release unless we
  # explicitly rebuild that context.
  def ensure_runtime_entities!
    return if skip_download?
    return if runtime_entities_ready?

    setup_entities
    return if skip_download?
    return if runtime_entities_ready?

    missing = []
    missing << "@source" unless @source
    missing << "@series" unless @series
    missing << "@chapter" unless @chapter
    missing << "@release" unless @release
    missing << "@file_asset" unless @file_asset

    raise "DownloadChapterJob: Runtime rehydration incomplete (missing #{missing.join(', ')})"
  end

  def runtime_entities_ready?
    @source && @series && @chapter && @release && @file_asset
  end

  def library_path_builder
    @library_path_builder ||= LibraryPathBuilder.new(series: @series, source: @source)
  end

  def skip_download?
    @skip_download == true
  end

  def stop_if_cancelled!
    return false unless @file_asset

    @file_asset.reload
    return false unless @file_asset.download_status == "cancelled"

    Rails.logger.info "DownloadChapterJob: FileAsset #{@file_asset.id} was cancelled, stopping"
    broadcast_chapter_update(@chapter, @source) if @chapter && @source
    true
  end
end
