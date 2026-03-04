class User < ApplicationRecord
  has_secure_password validations: false

  has_many :sessions, dependent: :destroy
  has_many :chapter_progresses, dependent: :destroy
  has_many :offline_manifest_entries, class_name: "UserOfflineManifestEntry", dependent: :destroy
  has_many :user_series_follows, dependent: :destroy
  has_many :followed_library_series, through: :user_series_follows, source: :library_series
  has_many :new_chapter_notifications, dependent: :destroy

  enum :role, { admin: 0, member: 1 }, default: :admin

  validates :email, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  before_save :generate_api_key
  before_validation :normalize_default_reading_style

  # JSONB preferences with typed accessors
  store_accessor :preferences,
    :default_reading_style,
    :default_language,
    :default_download_policy,
    :default_check_interval_minutes,
    :local_downloads_enabled,
    :notifications_enabled,
    :notification_auto_cleanup_days,
    :default_source_priority

  LANGUAGE_OPTIONS = [
    [ "Any", "" ],
    [ "English", "en" ],
    [ "Japanese", "ja" ],
    [ "Korean", "ko" ],
    [ "Chinese (Simplified)", "zh" ],
    [ "Chinese (Traditional)", "zh-hk" ],
    [ "Spanish", "es" ],
    [ "Portuguese (BR)", "pt-br" ],
    [ "French", "fr" ],
    [ "German", "de" ],
    [ "Italian", "it" ],
    [ "Russian", "ru" ],
    [ "Polish", "pl" ],
    [ "Thai", "th" ],
    [ "Vietnamese", "vi" ],
    [ "Indonesian", "id" ],
    [ "Arabic", "ar" ],
    [ "Turkish", "tr" ]
  ].freeze

  READING_STYLE_OPTIONS = ReadingStyles::OPTIONS

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
    self.class.normalize_reading_style(default_reading_style)
  end

  def effective_download_policy
    default_download_policy.presence || "auto_download"
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

  # Override reader so nil (unset) defaults to "false" for form binding
  def local_downloads_enabled
    val = super
    val.nil? ? "false" : val
  end

  def local_downloads_enabled?
    ActiveModel::Type::Boolean.new.cast(local_downloads_enabled)
  end

  def effective_cleanup_days
    notification_auto_cleanup_days.presence&.to_i
  end

  def setup_complete?
    password_digest.present? && username.present?
  end

  def regenerate_api_key!
    update!(api_key: self.class.generate_api_key)
  end

  def self.normalize_reading_style(value)
    ReadingStyles.normalize(value)
  end

  private

  def normalize_default_reading_style
    return if default_reading_style.blank?

    self.default_reading_style = self.class.normalize_reading_style(default_reading_style)
  end

  def generate_api_key
    self.api_key ||= self.class.generate_api_key
  end

  def self.generate_api_key
    "scanarr_#{SecureRandom.hex(24)}"
  end
end
