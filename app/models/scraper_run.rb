class ScraperRun < ApplicationRecord
  belongs_to :source

  STATUSES = %w[running success failed].freeze

  validates :run_type, :status, :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }
end
