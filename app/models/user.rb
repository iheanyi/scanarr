class User < ApplicationRecord
  # Simple user model for storing progress/follows
  # Authentication is handled by HTTP Basic Auth at the controller level

  has_many :chapter_progresses, dependent: :destroy
  has_many :user_series_follows, dependent: :destroy
  has_many :followed_library_series, through: :user_series_follows, source: :library_series
  has_many :new_chapter_notifications, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  # JSONB preferences with typed accessors
  store_accessor :preferences,
    :default_reading_style,
    :default_language,
    :default_download_policy,
    :default_check_interval_minutes,
    :notifications_enabled,
    :notification_auto_cleanup_days

  READING_STYLE_OPTIONS = [
    [ "Left to Right", "left_to_right" ],
    [ "Right to Left", "right_to_left" ],
    [ "Long Strip", "long_strip" ],
    [ "Webcomic", "webcomic" ]
  ].freeze

  DOWNLOAD_POLICY_OPTIONS = [
    [ "Notify Only", "notify_only" ],
    [ "Auto Download", "auto_download" ]
  ].freeze

  CLEANUP_DAYS_OPTIONS = [
    [ "Never", "" ],
    [ "After 7 days", "7" ],
    [ "After 14 days", "14" ],
    [ "After 30 days", "30" ],
    [ "After 90 days", "90" ]
  ].freeze

  def effective_reading_style
    default_reading_style.presence || "left_to_right"
  end

  def effective_download_policy
    default_download_policy.presence || "notify_only"
  end

  def effective_check_interval_minutes
    default_check_interval_minutes.presence&.to_i || UserSeriesFollow::DEFAULT_INTERVAL_MINUTES
  end

  # Override reader so nil (unset) defaults to "true" for form binding
  def notifications_enabled
    val = super
    val.nil? ? "true" : val
  end

  def notifications_enabled?
    ActiveModel::Type::Boolean.new.cast(notifications_enabled)
  end

  def effective_cleanup_days
    notification_auto_cleanup_days.presence&.to_i
  end
end
