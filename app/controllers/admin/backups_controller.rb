module Admin
  class BackupsController < AdminController
    before_action :set_backup, only: %i[download destroy verify]

    def index
      @backups = BackupRecord.recent.page(params[:page]).per(20)
      @stats = {
        total: BackupRecord.count,
        complete: BackupRecord.complete.count,
        failed: BackupRecord.failed.count,
        total_size: BackupRecord.complete.sum(:size)
      }
    end

    def create
      record = BackupRecord.create!(
        filename: "manual_#{Time.current.strftime('%Y%m%d_%H%M%S')}",
        backup_type: "manual",
        status: "pending"
      )

      CreateBackupJob.perform_later(record.id)

      respond_with_toast(
        redirect_path: admin_backups_path,
        message: "Backup started. It will appear in the list when complete.",
        variant: :success
      )
    end

    def download
      backup_path = resolved_backup_path(@backup)

      if backup_path
        send_file backup_path,
                  filename: @backup.filename,
                  type: "application/zip",
                  disposition: "attachment"
      else
        respond_with_toast(
          redirect_path: admin_backups_path,
          message: "Backup file not found on disk.",
          variant: :danger,
          status: :not_found
        )
      end
    end

    def destroy
      backup_path = resolved_backup_path(@backup)
      File.delete(backup_path) if backup_path
      @backup.destroy!

      respond_with_toast(
        redirect_path: admin_backups_path,
        message: "Backup deleted.",
        variant: :success,
        streams: [
          turbo_stream.remove(ActionView::RecordIdentifier.dom_id(@backup))
        ]
      )
    end

    def verify
      if @backup.file_exists?
        result = Backup::IntegrityChecker.new(backup_path: @backup.path).check
        if result.valid
          message = "Backup verified successfully.#{" Warnings: #{result.warnings.join(', ')}" if result.warnings.any?}"
          variant = :success
        else
          message = "Backup integrity check failed: #{result.errors.join(', ')}"
          variant = :danger
        end
      else
        message = "Backup file not found on disk."
        variant = :danger
      end

      respond_with_toast(
        redirect_path: admin_backups_path,
        message: message,
        variant: variant
      )
    end

    private

    def set_backup
      @backup = BackupRecord.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      respond_with_toast(
        redirect_path: admin_backups_path,
        message: "Backup not found",
        variant: :danger,
        status: :not_found,
        turbo_redirect: true
      )
      nil
    end

    def resolved_backup_path(backup)
      root = Backup::DatabaseBackupService::BACKUP_DIR.expand_path
      candidate = root.join(backup.filename).expand_path
      return nil unless candidate.to_s.start_with?("#{root}/")
      return nil unless File.file?(candidate)

      candidate.to_s
    end
  end
end
