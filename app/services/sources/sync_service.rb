# frozen_string_literal: true

module Sources
  # Syncs Source rows from config/sources/manifest.yml. Idempotent: re-running
  # against an unchanged manifest is a no-op. An adapter version bump records
  # the update and grants the source a fresh health probation, so old failure
  # evidence cannot keep a fixed source marked broken.
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
      source.capabilities = merged_capabilities(source, entry)

      # Operator toggles win over the manifest default, but a dead source is
      # force-disabled: there is nothing to scrape.
      source.enabled = false if entry.dead

      apply_version(source, entry)
    end

    def apply_version(source, entry)
      return if source.adapter_version == entry.version

      source.adapter_version = entry.version
      source.adapter_version_synced_at = Time.current
      source.health_status = "healthy"
      source.health_changed_at = Time.current
      source.rate_limited_until = nil
    end

    def merged_capabilities(source, entry)
      existing = source.capabilities.is_a?(Hash) ? source.capabilities.deep_stringify_keys : {}
      merged = existing.merge(entry.capabilities)
      merged.empty? ? nil : merged
    end
  end
end
