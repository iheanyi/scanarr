class CreateBackupJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "create_backup"

  def perform(backup_record_id)
    record = BackupRecord.find(backup_record_id)

    result = Backup::DatabaseBackupService.new.perform

    record.update!(
      filename: File.basename(result.path),
      path: result.path.to_s,
      size: result.size,
      checksum: result.checksum,
      status: "complete"
    )

    Rails.logger.info "[CreateBackupJob] Backup complete: #{result.path} (#{record.human_size})"
  rescue => error
    Rails.logger.error "[CreateBackupJob] Backup failed: #{error.message}"

    record = BackupRecord.find_by(id: backup_record_id)
    record&.update!(status: "failed", error_message: error.message)

    raise
  end
end
