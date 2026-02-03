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

    chapters.find_each do |chapter|
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
end
