class BackupRetentionCleanupJob < ApplicationJob
  queue_as :default

  DAILY_RETENTION  = 7
  WEEKLY_RETENTION = 4
  MONTHLY_RETENTION = 3

  def perform
    backups = BackupRecord.complete.order(created_at: :desc)
    return if backups.empty?

    keep = Set.new
    now = Time.current

    # Keep the N most recent daily backups
    backups.where("created_at > ?", DAILY_RETENTION.days.ago).each { |b| keep << b.id }

    # Keep one per week for the last N weeks
    (1..WEEKLY_RETENTION).each do |weeks_ago|
      week_start = now - weeks_ago.weeks
      week_end = week_start + 1.week
      weekly = backups.where(created_at: week_start..week_end).first
      keep << weekly.id if weekly
    end

    # Keep one per month for the last N months
    (1..MONTHLY_RETENTION).each do |months_ago|
      month_start = now - months_ago.months
      month_end = month_start + 1.month
      monthly = backups.where(created_at: month_start..month_end).first
      keep << monthly.id if monthly
    end

    # Delete everything not in the keep set
    to_delete = backups.where.not(id: keep.to_a)
    to_delete.find_each do |backup|
      Rails.logger.info "[BackupRetention] Removing old backup: #{backup.filename}"
      File.delete(backup.path) if backup.path.present? && File.exist?(backup.path)
      backup.destroy!
    end
  end
end
