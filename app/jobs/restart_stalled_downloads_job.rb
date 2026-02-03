# frozen_string_literal: true

class RestartStalledDownloadsJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "restart_stalled_downloads"

  STALL_THRESHOLD = 5.minutes

  def perform
    stalled_assets = FileAsset
      .where(download_status: "downloading")
      .where("updated_at < ?", STALL_THRESHOLD.ago)

    count = stalled_assets.count
    return if count.zero?

    Rails.logger.info "[RestartStalledDownloadsJob] Found #{count} stalled downloads, re-enqueuing..."

    stalled_assets.find_each do |file_asset|
      restart_download(file_asset)
    end

    Rails.logger.info "[RestartStalledDownloadsJob] Re-enqueued #{count} stalled downloads"
  end

  private

  def restart_download(file_asset)
    release = file_asset.release
    chapter = release&.chapter
    source = chapter&.source || release&.source

    return unless chapter && source

    # Reset status to queued
    file_asset.update!(
      download_status: "queued",
      download_error: nil
    )

    # Re-enqueue the download job
    DownloadChapterJob.perform_later(
      chapter.id,
      source.key,
      release_id: release.id
    )

    Rails.logger.info "[RestartStalledDownloadsJob] Re-enqueued chapter #{chapter.id} (#{chapter.title})"
  rescue StandardError => e
    Rails.logger.error "[RestartStalledDownloadsJob] Failed to restart #{file_asset.id}: #{e.message}"
  end
end
