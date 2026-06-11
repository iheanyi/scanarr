# frozen_string_literal: true

module Scrapers
  class AdapterRegistry
    class UnknownSourceError < StandardError; end

    class << self
      def for(source_or_key, base_url: nil)
        key = source_or_key.is_a?(String) ? source_or_key : source_or_key.key
        adapter_for_key(key, base_url: base_url)
      end

      def adapter_for_key(key, base_url: nil)
        entry = Manifest.entry_for(key)
        raise UnknownSourceError, "Unknown source: #{key}" unless entry

        entry.adapter_class.new(config: source_config(entry, base_url_override: base_url))
      end

      def registered_keys
        Manifest.keys
      end

      def registered?(key)
        Manifest.entry_for(key).present?
      end

      private

      # base_url precedence, lowest to highest: manifest, a domain adopted from
      # the upstream catalog after it healed a broken source, the operator's
      # config/sources.yml override, an explicit caller override (probes).
      def source_config(entry, base_url_override: nil)
        config = { "base_url" => adopted_base_url(entry.key) || entry.base_url }
        config = config.merge(operator_overrides(entry.key))
        config["base_url"] = base_url_override if base_url_override
        config
      end

      def adopted_base_url(key)
        Source.find_by(key: key)&.adopted_base_url.presence
      end

      def operator_overrides(key)
        Rails.application.config_for(:sources).fetch(key.to_sym, {}).to_h.deep_stringify_keys
      rescue RuntimeError
        {}
      end
    end
  end
end
