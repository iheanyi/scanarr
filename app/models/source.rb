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

  # -- Health and domain transitions ------------------------------------
  # Every transition below resets ALL the evidence it invalidates. The bug
  # class that dominated PR #52's review was partial resets: a transition
  # that moved one piece of state (health, window anchor, streaks, adopted
  # domain) and left another stale. Add new transitions here, not at call
  # sites.
  #
  # Non-bang methods assign without saving so SyncService's changed?-based
  # idempotency bookkeeping stays intact; bang methods persist immediately.

  def assign_health(status)
    return if health_status == status

    self.health_status = status
    self.health_changed_at = Time.current
  end

  # Manifest says dead: force-disabled and health pinned so scheduled work
  # skips it. Sync is the only way back out (see HealthEvaluator).
  def pin_dead
    self.enabled = false
    assign_health("dead")
  end

  # A fresh start after a version bump or resurrection: the evidence window
  # moves, per-series failure streaks restart (a fixed adapter should retry
  # series that were failing, including ones stale-listed at 10+), the rate
  # limit clears, and a stale adopted domain stops outranking the manifest.
  def grant_probation
    assign_health("healthy")
    self.adapter_version_synced_at = Time.current
    self.rate_limited_until = nil
    self.adopted_base_url = nil
    restore_series_streaks! unless new_record?
  end

  # Runtime health writes converge here (sweep recheck, admin smoke, the
  # chapter-check failure path), so the broken-to-healthy streak restore
  # cannot be skipped by any heal path.
  def transition_health!(status)
    unless health_status == status
      was_broken = broken?
      update!(health_status: status, health_changed_at: Time.current)
      restore_series_streaks! if was_broken && status == "healthy"
    end
    status
  end

  # Sticky domain adoption after recovery. Stored chapter and release URLs
  # are absolute on the dead domain and feed straight into adapter.pages,
  # so they move with the adoption.
  def adopt_domain!(new_base_url)
    previous = adopted_base_url.presence || Scrapers::Manifest.entry_for(key)&.base_url
    update!(adopted_base_url: new_base_url)
    remap_stored_urls(previous, new_base_url)
  end

  # ----------------------------------------------------------------------

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

  # The domain scraping actually uses, from the registry's full precedence
  # chain (manifest < adoption < operator pin). Falls back for sources
  # without a manifest entry.
  def effective_base_url
    Scrapers::AdapterRegistry.effective_base_url(key) || adopted_base_url.presence || base_url
  end

  def display_name
    name.presence || key
  end

  def display_name_with_content_rating
    mature_content? ? "#{display_name} (18+)" : display_name
  end

  private

  def restore_series_streaks!
    series_sources.where("consecutive_failures > 0").update_all(consecutive_failures: 0)
  end

  def remap_stored_urls(old_base, new_base)
    old_prefix = old_base.to_s.chomp("/")
    new_prefix = new_base.to_s.chomp("/")
    return if old_prefix.blank? || old_prefix == new_prefix

    [ chapters, releases ].each do |scope|
      scope.where("source_url LIKE ?", "#{self.class.sanitize_sql_like(old_prefix)}%")
        .update_all([ "source_url = REPLACE(source_url, ?, ?)", old_prefix, new_prefix ])
    end
  end

  def generate_slug_from_key
    self.slug = key.to_s.tr("_", "-") if key.present? && (slug.blank? || key_changed?)
  end
end
