class Source < ApplicationRecord
  MATURE_SOURCE_KEYS = %w[manhwa18 toonily].freeze
  MATURE_CAPABILITY_KEY = "mature_content".freeze

  has_many :series_sources, dependent: :destroy
  has_many :series, through: :series_sources
  has_many :chapters, dependent: :nullify
  has_many :releases, dependent: :nullify
  has_many :scraper_runs, dependent: :destroy

  validates :key, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug_from_key

  # Calculate reliability score based on recent scraper run success rate
  # Returns a decimal between 0.0 and 1.0
  def reliability_score
    recent_runs = scraper_runs.where("created_at > ?", 30.days.ago)
    return 0.5 if recent_runs.empty? # Default to neutral if no history

    successful = recent_runs.where(status: "success").count
    total = recent_runs.count

    (successful.to_f / total).round(2)
  end

  # Check if this source is currently rate-limited
  def rate_limited?
    rate_limited_until.present? && rate_limited_until > Time.current
  end

  # Record a rate limit, preventing checks for the given duration
  def record_rate_limit!(duration = 5.minutes)
    update!(rate_limited_until: duration.from_now)
  end

  # Clear any active rate limit
  def clear_rate_limit!
    update!(rate_limited_until: nil) if rate_limited_until.present?
  end

  def mature_content?
    capabilities_hash = capabilities.is_a?(Hash) ? capabilities : {}
    explicit_flag = if capabilities_hash.key?(MATURE_CAPABILITY_KEY)
      capabilities_hash[MATURE_CAPABILITY_KEY]
    elsif capabilities_hash.key?(MATURE_CAPABILITY_KEY.to_sym)
      capabilities_hash[MATURE_CAPABILITY_KEY.to_sym]
    end

    return ActiveModel::Type::Boolean.new.cast(explicit_flag) unless explicit_flag.nil?

    self.class.mature_source_key?(key)
  end

  def display_name
    name.presence || key
  end

  def display_name_with_content_rating
    mature_content? ? "#{display_name} (18+)" : display_name
  end

  class << self
    def mature_source_key?(source_key)
      MATURE_SOURCE_KEYS.include?(source_key.to_s)
    end
  end

  private

  def generate_slug_from_key
    self.slug = key.to_s.tr("_", "-") if key.present? && (slug.blank? || key_changed?)
  end
end
