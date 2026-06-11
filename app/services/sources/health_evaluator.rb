# frozen_string_literal: true

module Sources
  # Derives a source's health from existing signals: smoke-run history and
  # per-series check failures. Evidence is windowed to the last adapter
  # version bump, so a shipped fix starts from a clean slate instead of being
  # damned by stale failures. Recomputation is idempotent: the status is a
  # pure function of current signals.
  #
  # "dead" is curated through the manifest (`dead: true`), never derived, so a
  # transient Cloudflare block can't bury a working source.
  class HealthEvaluator
    BROKEN_RUN_STREAK = 3
    MIN_TRACKED_SERIES = 4
    BROKEN_SERIES_RATIO = 0.75
    DEGRADED_SERIES_RATIO = 0.25

    def initialize(source)
      @source = source
    end

    def call
      status = derived_status
      unless @source.health_status == status
        was_broken = @source.broken?
        @source.update!(health_status: status, health_changed_at: Time.current)
        # Every heal path converges here (sweep recheck, admin smoke, the
        # chapter-check failure path), so this is the one place to un-stale
        # series whose 10+ failure streaks only ever reflected the outage.
        restore_series! if was_broken && status == "healthy"
      end
      status
    end

    def derived_status
      return "dead" if @source.dead?
      return "broken" if smoke_streak_broken? || series_failure_ratio >= BROKEN_SERIES_RATIO
      return "degraded" if last_smoke_failed? || series_failure_ratio >= DEGRADED_SERIES_RATIO || @source.rate_limited?

      "healthy"
    end

    private

    def restore_series!
      @source.series_sources.where("consecutive_failures > 0").update_all(consecutive_failures: 0)
    end

    def smoke_streak_broken?
      recent_run_statuses.size >= BROKEN_RUN_STREAK && recent_run_statuses.all?("failed")
    end

    def last_smoke_failed?
      recent_run_statuses.first == "failed"
    end

    # Newest-first statuses of the last few finished runs in the window.
    def recent_run_statuses
      @recent_run_statuses ||= windowed(@source.scraper_runs)
        .where(status: %w[success failed])
        .order(created_at: :desc)
        .limit(BROKEN_RUN_STREAK)
        .pluck(:status)
    end

    def series_failure_ratio
      @series_failure_ratio ||= begin
        tracked = attempted_series.count
        if tracked < MIN_TRACKED_SERIES
          0.0
        else
          failing = @source.series_sources.where("consecutive_failures >= 3")
          failing = failing.where(last_check_error_at: series_evidence_cutoff..) if series_evidence_cutoff
          failing.count.to_f / tracked
        end
      end
    end

    # The denominator must use the same evidence window as the numerator:
    # counting every series ever checked would dilute fresh failures into a
    # healthy-looking ratio on a source with a long history. A series whose
    # checks have only ever failed never gets last_checked_at set, so error
    # timestamps count as attempts too.
    def attempted_series
      scope = @source.series_sources
      if series_evidence_cutoff
        scope.where(last_checked_at: series_evidence_cutoff..)
          .or(scope.where(last_check_error_at: series_evidence_cutoff..))
      else
        scope.where.not(last_checked_at: nil).or(scope.where.not(last_check_error_at: nil))
      end
    end

    # Series failures recorded before the last version bump or the last
    # successful run are stale evidence. Without this cutoff a broken source
    # whose checks are skipped could never recover: a successful recheck must
    # outweigh failure rows that nothing will ever update.
    def series_evidence_cutoff
      return @series_evidence_cutoff if defined?(@series_evidence_cutoff)

      latest_success_at = windowed(@source.scraper_runs).where(status: "success").maximum(:created_at)
      @series_evidence_cutoff = [ @source.adapter_version_synced_at, latest_success_at ].compact.max
    end

    def windowed(runs)
      synced_at = @source.adapter_version_synced_at
      synced_at ? runs.where(created_at: synced_at..) : runs
    end
  end
end
