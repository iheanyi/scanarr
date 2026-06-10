# frozen_string_literal: true

class CleanupOrphanedDownloadsJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "cleanup_orphaned_downloads"

  def perform
    orphaned_count = 0

    FileAsset.where(download_status: "complete").find_each do |file_asset|
      # Spot-check: verify first page's blob exists on disk
      first_page = file_asset.pages.includes(image_attachment: :blob).order(:position).first
      next unless first_page&.image&.blob

      unless ActiveStorage::Blob.service.exist?(first_page.image.blob.key)
        file_asset.update!(
          download_status: "failed",
          download_error: FileAsset::ORPHANED_BLOBS_ERROR
        )
        orphaned_count += 1
        Rails.logger.warn "[CleanupOrphanedDownloadsJob] Marked file_asset #{file_asset.id} as failed (orphaned blobs)"
      end
    end

    Rails.logger.info "[CleanupOrphanedDownloadsJob] Found #{orphaned_count} orphaned downloads"
  end
end
