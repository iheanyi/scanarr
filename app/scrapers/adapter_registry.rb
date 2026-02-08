# frozen_string_literal: true

class AdapterRegistry
  class UnknownSourceError < StandardError; end

  ADAPTERS = {
    "mangadex" => -> { Mangadex::Adapter },
    "weeb_central" => -> { WeebCentral::Adapter },
    "manga_see" => -> { MangaSee::Adapter },
    "asura_scans" => -> { AsuraScans::Adapter },
    "manga_pill" => -> { MangaPill::Adapter },
    "comick" => -> { Comick::Adapter }
  }.freeze

  class << self
    def for(source_or_key)
      key = source_or_key.is_a?(String) ? source_or_key : source_or_key.key
      adapter_for_key(key)
    end

    def adapter_for_key(key)
      adapter_proc = ADAPTERS[key]
      raise UnknownSourceError, "Unknown source: #{key}" unless adapter_proc

      config = source_config(key)
      adapter_proc.call.new(config: config)
    end

    def registered_keys
      ADAPTERS.keys
    end

    def registered?(key)
      ADAPTERS.key?(key)
    end

    private

    def source_config(key)
      Rails.application.config_for(:sources).fetch(key.to_sym, {}).to_h.deep_stringify_keys
    rescue RuntimeError
      {}
    end
  end
end
