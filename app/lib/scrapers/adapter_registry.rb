# frozen_string_literal: true

module Scrapers
  class AdapterRegistry
    class UnknownSourceError < StandardError; end

    class << self
      def for(source_or_key)
        key = source_or_key.is_a?(String) ? source_or_key : source_or_key.key
        adapter_for_key(key)
      end

      def adapter_for_key(key)
        entry = Manifest.entry_for(key)
        raise UnknownSourceError, "Unknown source: #{key}" unless entry

        entry.adapter_class.new(config: source_config(entry))
      end

      def registered_keys
        Manifest.keys
      end

      def registered?(key)
        Manifest.entry_for(key).present?
      end

      private

      # Manifest provides the canonical base_url; config/sources.yml remains an
      # operator override layer for HTTP tuning (timeouts, delays, proxies).
      def source_config(entry)
        { "base_url" => entry.base_url }.merge(operator_overrides(entry.key))
      end

      def operator_overrides(key)
        Rails.application.config_for(:sources).fetch(key.to_sym, {}).to_h.deep_stringify_keys
      rescue RuntimeError
        {}
      end
    end
  end
end
