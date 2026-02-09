# frozen_string_literal: true

class TachiyomiSourceMapper
  class << self
    # Import direction: Tachiyomi source ID → Scanarr adapter key
    def scanarr_key_for(tachiyomi_id)
      source_map[tachiyomi_id.to_i]
    end

    # Export direction: Scanarr adapter key → Tachiyomi source ID
    def tachiyomi_id_for(scanarr_key)
      export_map[scanarr_key.to_s]
    end

    # Check if a Tachiyomi source ID is mapped to any Scanarr adapter
    def known?(tachiyomi_id)
      source_map.key?(tachiyomi_id.to_i) || future_source_map.key?(tachiyomi_id.to_i)
    end

    # Returns unmapped source IDs from a parsed backup
    def unmapped_sources(backup)
      backup.backupManga.map(&:source).uniq.reject { |id| source_map.key?(id) }
    end

    # Returns source name from backup's backupSources list for a given ID
    def source_name_from_backup(backup, source_id)
      backup.backupSources.find { |s| s.sourceId == source_id }&.name
    end

    # Returns the future source name if we know it but don't have an adapter
    def future_source_name(tachiyomi_id)
      future_source_map[tachiyomi_id.to_i]
    end

    private

    def config
      @config ||= YAML.load_file(Rails.root.join("config", "tachiyomi_source_map.yml"))
    end

    def source_map
      @source_map ||= config["sources"].transform_keys(&:to_i)
    end

    def export_map
      @export_map ||= config["export_ids"].transform_values(&:to_i)
    end

    def future_source_map
      @future_source_map ||= config["future_sources"].transform_keys(&:to_i)
    end
  end
end
