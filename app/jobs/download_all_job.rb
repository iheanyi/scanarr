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
    enqueued = 0
    seen_numbers = Set.new

    chapters.order(created_at: :desc).find_each do |chapter|
      # Skip duplicate chapter numbers (e.g. different language/group variants)
      next if seen_numbers.include?(chapter.chapter_number)
      seen_numbers.add(chapter.chapter_number)
      next if chapter.source_url.blank?

      # Skip if already downloaded or in progress
      latest_release = chapter.releases.max_by(&:created_at)
      file_asset = latest_release&.file_asset
      next if file_asset&.download_status.in?(%w[queued pending downloading complete])

      # Create or find release
      release = chapter.releases.find_or_create_by!(source: source)

      # Skip if this release already has a complete/in-progress download
      if release.file_asset&.download_status.in?(%w[queued pending downloading complete])
        next
      end

      # Create file_asset with "queued" status immediately so UI shows it
      file_asset = release.file_asset || release.create_file_asset!(
        format: "pages",
        download_status: "queued",
        pages_downloaded: 0
      )

      # Broadcast immediately so UI updates
      broadcast_chapter_update(chapter, source, series)
      broadcast_admin_download_update(file_asset)

      DownloadChapterJob.perform_later(
        chapter.source_url,
        source_key: source.key,
        series_title: series.canonical_title,
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

  def broadcast_admin_download_update(file_asset)
    # Prepend new download to the admin downloads table
    Turbo::StreamsChannel.broadcast_prepend_to(
      "admin_downloads",
      target: "downloads_list",
      partial: "admin/downloads/download_row",
      locals: { download: file_asset }
    )
  rescue StandardError => e
    Rails.logger.warn "DownloadAllJob: Failed to broadcast admin download: #{e.message}"
  end
end
