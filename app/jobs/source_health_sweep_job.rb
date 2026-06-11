# frozen_string_literal: true

# Recomputes every source's health from passive signals (smoke-run history,
# per-series check failures). Broken sources get one cheap recheck probe on a
# backoff schedule; everything else stays network-free. The recheck is the
# recovery path: scheduled chapter checks skip broken sources, so without it
# a returning site would never produce a fresh signal and could never heal.
class SourceHealthSweepJob < ApplicationJob
  queue_as :default

  # Backoff by how long the source has been broken: eager for fresh breakage,
  # polite for sites that have been gone for weeks.
  RECHECK_BACKOFF = [
    [ 3.days, 6.hours ],
    [ 14.days, 24.hours ]
  ].freeze
  LONG_DOWNTIME_RECHECK_INTERVAL = 7.days

  def perform
    Source.find_each do |source|
      # Operator-disabled sources get no probe traffic; passive evaluation
      # still runs so their health stays current if signals exist. The two
      # steps are rescued independently: a recheck failure must not skip the
      # evaluation that would consume its evidence.
      begin
        if source.enabled? && source.broken? && recheck_due?(source)
          Sources::BrokenSourceRecheck.new(source).call
        end
      rescue StandardError => e
        Rails.logger.error "[SourceHealthSweepJob] recheck #{source.key}: #{e.message}"
      end

      begin
        Sources::HealthEvaluator.new(source).call
      rescue StandardError => e
        Rails.logger.error "[SourceHealthSweepJob] evaluate #{source.key}: #{e.message}"
      end
    end
  end

  private

  # Only runs since the source entered its current (broken) state count as
  # recovery attempts; a success just before the breakage must not suppress
  # the first probe for a full backoff interval.
  def recheck_due?(source)
    attempts = source.scraper_runs.where(status: %w[success failed])
    attempts = attempts.where(created_at: source.health_changed_at..) if source.health_changed_at
    last_attempt = attempts.maximum(:created_at)
    return true if last_attempt.nil?

    last_attempt < recheck_interval(source).ago
  end

  def recheck_interval(source)
    broken_for = Time.current - (source.health_changed_at || Time.current)
    RECHECK_BACKOFF.each do |max_age, interval|
      return interval if broken_for < max_age
    end
    LONG_DOWNTIME_RECHECK_INTERVAL
  end
end
