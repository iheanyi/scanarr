class ScheduledBackupJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "scheduled_backup"

  def perform
    Rails.logger.info "[ScheduledBackupJob] Starting automated backup"

    result = Backup::DatabaseBackupService.new.perform

    BackupRecord.create!(
      filename: File.basename(result.path),
      path: result.path.to_s,
      size: result.size,
      checksum: result.checksum,
      backup_type: "scheduled",
      status: "complete"
    )

    Rails.logger.info "[ScheduledBackupJob] Backup complete: #{result.path} (#{ActiveSupport::NumberHelper.number_to_human_size(result.size)})"
  rescue => error
    Rails.logger.error "[ScheduledBackupJob] Backup failed: #{error.message}"

    BackupRecord.create!(
      filename: "failed_#{Time.current.strftime('%Y%m%d_%H%M%S')}",
      backup_type: "scheduled",
      status: "failed",
      error_message: error.message
    )

    raise
  end
end
