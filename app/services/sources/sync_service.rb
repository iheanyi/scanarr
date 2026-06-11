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

      # Operator toggles win over the manifest default. Dead pinning and
      # probation semantics live on Source; sync just decides which
      # transition the manifest asks for.
      if entry.dead
        source.pin_dead
      elsif source.health_status == "dead"
        source.grant_probation
      end

      apply_version(source, entry)
    end

    def apply_version(source, entry)
      return if source.adapter_version == entry.version

      source.adapter_version = entry.version
      source.grant_probation
      source.assign_health("dead") if entry.dead
    end
  end
end
