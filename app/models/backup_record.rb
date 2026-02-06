class BackupRecord < ApplicationRecord
  validates :filename, presence: true
  validates :backup_type, presence: true, inclusion: { in: %w[scheduled manual pre_restore pre_import] }
  validates :status, presence: true, inclusion: { in: %w[pending complete failed] }

  scope :complete, -> { where(status: "complete") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  def human_size
    return nil unless size

    ActiveSupport::NumberHelper.number_to_human_size(size)
  end

  def file_exists?
    path.present? && File.exist?(path)
  end
end
