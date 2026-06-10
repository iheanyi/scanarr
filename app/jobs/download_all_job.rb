class DownloadAllJob < ApplicationJob
  queue_as :default

  # Only one "download all" job per series at a time
  limits_concurrency to: 1, key: ->(series_id, source_id) { "download_all:#{series_id}:#{source_id}" }

  def perform(series_id, source_id)
    series = Series.find_by(id: series_id)
    source = Source.find_by(id: source_id)

    unless series && source
      Rails.logger.info "DownloadAllJob: Series or source no longer exists, skipping"
      return
    end

    chapters = series.chapters.where(source: source).includes(releases: :file_asset)
    series_source = series.series_sources.find_by(source: source)
    enqueued = 0
    seen_numbers = Set.new

    chapters.order(created_at: :desc).find_each do |chapter|
      # Skip duplicate chapter numbers (e.g. different language/group variants)
      next if seen_numbers.include?(chapter.chapter_number)
      seen_numbers.add(chapter.chapter_number)
      next if chapter.source_url.blank?

      # Skip if already downloaded or in progress
      latest_release = chapter.releases.to_a.max_by(&:created_at)
      file_asset = latest_release&.file_asset
      next if file_asset&.download_status.in?(%w[queued pending downloading complete])

      release = latest_release || chapter.releases.find_or_create_by!(source: source)

      # Skip if this release already has a complete/in-progress download
      if release.file_asset&.download_status.in?(%w[queued pending downloading complete])
        next
      end

      chapter_path = LibraryPathBuilder.new(series: series, source: source).chapter_path(chapter)
      existing_file_asset = release.file_asset
      file_asset = if existing_file_asset
        existing_file_asset.tap do |asset|
          asset.update!(
            download_status: "queued",
            pages_downloaded: 0,
            pages_expected: nil,
            download_error: nil,
            path: chapter_path
          )
        end
      else
        release.create_file_asset!(
          format: "pages",
          download_status: "queued",
          pages_downloaded: 0,
          path: chapter_path
        )
      end

      # Broadcast immediately so UI updates
      broadcast_chapter_update(chapter, source, series)
      broadcast_admin_download_update(file_asset, existing: existing_file_asset.present?)

      DownloadChapterJob.perform_later(
        chapter.source_url,
        source_key: source.key,
        series_title: series.canonical_title,
        source_series_id: series_source&.source_series_id,
        chapter_number: chapter.chapter_number,
        chapter_title: chapter.title,
        language: chapter.language,
        group: chapter.group,
        release_id: release.id
      )
      enqueued += 1
    end

    Rails.logger.info "DownloadAllJob: Enqueued #{enqueued} chapter downloads for #{series.canonical_title}"
  end

  private

  def broadcast_chapter_update(chapter, source, series)
    chapter.reload
    latest_release = chapter.releases.includes(:file_asset).order(created_at: :desc).first
    Turbo::StreamsChannel.broadcast_replace_to(
      [ series, :downloads ],
      target: ActionView::RecordIdentifier.dom_id(chapter),
      partial: "series/chapter_row",
      locals: { chapter: chapter, source: source, series: series, progress: nil, latest_release: latest_release }
    )
  rescue StandardError => e
    Rails.logger.warn "DownloadAllJob: Failed to broadcast chapter update: #{e.message}"
  end

  def broadcast_admin_download_update(file_asset, existing:)
    if existing
      Turbo::StreamsChannel.broadcast_replace_to(
        "admin_downloads",
        target: ActionView::RecordIdentifier.dom_id(file_asset),
        partial: "admin/downloads/download_row",
        locals: { download: file_asset }
      )
    else
      Turbo::StreamsChannel.broadcast_prepend_to(
        "admin_downloads",
        target: "downloads_list",
        partial: "admin/downloads/download_row",
        locals: { download: file_asset }
      )
    end
  rescue StandardError => e
    Rails.logger.warn "DownloadAllJob: Failed to broadcast admin download: #{e.message}"
  end
end
