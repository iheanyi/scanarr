class Source < ApplicationRecord
  include AASM

  MATURE_CAPABILITY_KEY = "mature_content".freeze

  has_many :series_sources, dependent: :destroy
  has_many :series, through: :series_sources
  has_many :chapters, dependent: :nullify
  has_many :releases, dependent: :nullify
  has_many :scraper_runs, dependent: :destroy

  enum :health_status, { healthy: "healthy", degraded: "degraded", broken: "broken", dead: "dead" }, validate: true

  # Health is DERIVED, not event-driven: HealthEvaluator recomputes status
  # from evidence and the model fires the matching mark_* event, so every
  # live state is reachable from every other. What the machine buys us is
  # edges with declared consequences: the evidence reset lives on the
  # transition that invalidates it, so a caller cannot heal a source and
  # forget the per-series streak restore (the partial-reset bug class from
  # PR #52 review).
  #
  # "dead" is curated through the manifest, never derived: only pin_dead
  # enters it and only resurrect leaves it. Non-bang events assign in
  # memory so SyncService's changed?-based idempotency stays intact; the
  # evaluator persists through transition_health!.
  aasm column: :health_status, enum: true, create_scopes: false, whiny_persistence: true do
    state :healthy, initial: true
    state :degraded
    state :broken
    state :dead

    after_all_transitions :touch_health_changed_at

    # Any heal restores per-series streaks: a degraded source can carry a
    # minority of series stale-listed at 10+ failures, and scheduled checks
    # would skip those forever after recovery.
    event :mark_healthy do
      transitions from: [ :broken, :degraded ], to: :healthy, after: :restore_series_streaks!
    end

    event :mark_degraded do
      transitions from: [ :healthy, :broken ], to: :degraded
    end

    event :mark_broken do
      transitions from: [ :healthy, :degraded ], to: :broken
    end

    event :pin_dead do
      transitions from: [ :healthy, :degraded, :broken ], to: :dead
    end

    event :resurrect do
      transitions from: :dead, to: :healthy, after: :reset_probation_evidence
    end
  end

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

  # -- Transition entry points -------------------------------------------

  # Runtime health writes converge here (sweep recheck, admin smoke, the
  # chapter-check failure path). The derivation hands us a target status;
  # the machine enforces the edge and its declared consequences.
  def transition_health!(status)
    return status if health_status == status

    public_send(:"mark_#{status}!")
    status
  end

  # A fresh start after an adapter version bump: the evidence window moves,
  # per-series failure streaks restart (a fixed adapter should retry series
  # that were failing, including ones stale-listed at 10+), the rate limit
  # clears, and a stale adopted domain stops outranking the manifest. This
  # is deliberately not an event: a bump on an already-healthy source resets
  # evidence with no state change, and a bump on a dead entry stays dead.
  def grant_probation
    mark_healthy if may_mark_healthy?
    reset_probation_evidence
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

  def touch_health_changed_at
    self.health_changed_at = Time.current
  end

  def reset_probation_evidence
    self.adapter_version_synced_at = Time.current
    self.rate_limited_until = nil
    self.adopted_base_url = nil
    restore_series_streaks! unless new_record?
  end

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
