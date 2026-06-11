class Source < ApplicationRecord
  MATURE_CAPABILITY_KEY = "mature_content".freeze

  has_many :series_sources, dependent: :destroy
  has_many :series, through: :series_sources
  has_many :chapters, dependent: :nullify
  has_many :releases, dependent: :nullify
  has_many :scraper_runs, dependent: :destroy

  enum :health_status, { healthy: "healthy", degraded: "degraded", broken: "broken", dead: "dead" }, validate: true

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

    manifest_capability = Scrapers::Manifest.entry_for(key)&.capabilities&.fetch(MATURE_CAPABILITY_KEY, nil)
    ActiveModel::Type::Boolean.new.cast(manifest_capability) || false
  end

  # Why a source cannot receive migrations, or nil when it can. Shared by the
  # bulk service and the per-series controller so the link-then-validate
  # ordering cannot diverge between the two paths.
  def migration_target_rejection
    return "disabled" unless enabled?
    return health_status if broken? || dead?

    nil
  end

  # The domain scraping actually uses: a sticky adoption from health
  # recovery outranks the manifest-synced column (mirrors AdapterRegistry).
  def effective_base_url
    adopted_base_url.presence || base_url
  end

  def display_name
    name.presence || key
  end

  def display_name_with_content_rating
    mature_content? ? "#{display_name} (18+)" : display_name
  end

  private

  def generate_slug_from_key
    self.slug = key.to_s.tr("_", "-") if key.present? && (slug.blank? || key_changed?)
  end
end
