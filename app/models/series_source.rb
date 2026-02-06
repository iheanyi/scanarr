class SeriesSource < ApplicationRecord
  belongs_to :series
  belongs_to :source

  scope :with_errors, -> { where.not(last_check_error: nil) }
  scope :healthy, -> { where(last_check_error: nil) }
  scope :stale, -> { where("consecutive_failures >= ?", 10) }
  scope :needs_attention, -> { where("consecutive_failures >= ? AND consecutive_failures < ?", 3, 10) }

  # Record a successful check, clearing any previous errors
  def record_check_success!
    update!(
      last_checked_at: Time.current,
      last_check_error: nil,
      last_check_error_at: nil,
      consecutive_failures: 0
    )
  end

  # Record a failed check with the error message
  def record_check_failure!(error_message)
    update!(
      last_check_error: error_message.to_s.truncate(500),
      last_check_error_at: Time.current,
      consecutive_failures: consecutive_failures + 1
    )
  end

  def check_failing?
    consecutive_failures > 0
  end

  def check_critically_failing?
    consecutive_failures >= 3
  end

  def stale?
    consecutive_failures >= 10
  end
end
