module Admin
  class BackupsController < ApplicationController
    before_action :require_admin

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

      flash[:notice] = "Backup started. It will appear in the list when complete."
      redirect_to admin_backups_path
    end

    def download
      @backup = BackupRecord.find(params[:id])

      if @backup.file_exists?
        send_file @backup.path,
                  filename: @backup.filename,
                  type: "application/zip",
                  disposition: "attachment"
      else
        flash[:alert] = "Backup file not found on disk."
        redirect_to admin_backups_path
      end
    end

    def destroy
      @backup = BackupRecord.find(params[:id])
      File.delete(@backup.path) if @backup.file_exists?
      @backup.destroy!

      flash[:notice] = "Backup deleted."
      redirect_to admin_backups_path
    end

    def verify
      @backup = BackupRecord.find(params[:id])

      if @backup.file_exists?
        result = Backup::IntegrityChecker.new(backup_path: @backup.path).check
        if result.valid
          flash[:notice] = "Backup verified successfully.#{" Warnings: #{result.warnings.join(', ')}" if result.warnings.any?}"
        else
          flash[:alert] = "Backup integrity check failed: #{result.errors.join(', ')}"
        end
      else
        flash[:alert] = "Backup file not found on disk."
      end

      redirect_to admin_backups_path
    end
  end
end
