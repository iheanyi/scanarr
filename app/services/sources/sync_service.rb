# frozen_string_literal: true

module Sources
  # Syncs Source rows from config/sources/manifest.yml. Idempotent: re-running
  # against an unchanged manifest is a no-op. An adapter version bump records
  # the update and grants the source a fresh health probation, so old failure
  # evidence cannot keep a fixed source marked broken.
  #
  # The capabilities column is operator-owned and never written here: manifest
  # capabilities are consulted at runtime (see Source#mature_content?), so a
  # manifest change or removal takes effect without fighting stale synced
  # copies, and explicit operator overrides keep winning.
  class SyncService
    Result = Data.define(:created, :updated, :unchanged)

    def initialize(entries: Scrapers::Manifest.entries)
      @entries = entries
    end

    def call
      created = []
      updated = []
      unchanged = []

      @entries.each do |entry|
        source = Source.find_or_initialize_by(key: entry.key)

        if source.new_record?
          apply_entry(source, entry)
          source.enabled = entry.enabled && !entry.dead
          source.save!
          created << source
          next
        end

        apply_entry(source, entry)
        if source.changed?
          source.save!
          updated << source
        else
          unchanged << source
        end
      end

      Result.new(created:, updated:, unchanged:)
    end

    private

    def apply_entry(source, entry)
      source.name = entry.name
      source.base_url = entry.base_url
      source.source_type = entry.source_type
      source.default_priority = entry.priority

      # Operator toggles win over the manifest default, but a dead source is
      # force-disabled and its health pinned to dead so scheduled work skips
      # it: there is nothing to scrape. Sync is also the only way out of dead
      # (the evaluator keeps it sticky), so a resurrected entry gets a fresh
      # healthy probation for the evaluator to re-derive from.
      if entry.dead
        source.enabled = false
        assign_health(source, "dead")
      elsif source.health_status == "dead"
        grant_probation(source)
      end

      apply_version(source, entry)
    end

    def apply_version(source, entry)
      return if source.adapter_version == entry.version

      source.adapter_version = entry.version
      grant_probation(source)
      assign_health(source, "dead") if entry.dead
    end

    # A fresh probation must reset every piece of failure evidence, or the
    # evaluator re-derives broken from stale signals: the window anchor moves,
    # per-series failure streaks restart (a fixed adapter should retry series
    # that were failing, including ones stale-listed at 10+), the rate limit
    # clears, and a stale adopted domain stops outranking the manifest URL.
    def grant_probation(source)
      assign_health(source, "healthy")
      source.adapter_version_synced_at = Time.current
      source.rate_limited_until = nil
      source.adopted_base_url = nil
      source.series_sources.update_all(consecutive_failures: 0) unless source.new_record?
    end

    def assign_health(source, status)
      return if source.health_status == status

      source.health_status = status
      source.health_changed_at = Time.current
    end
  end
end
