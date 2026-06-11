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

      # An operator pin in config/sources.yml outranks any adopted domain, so
      # callers like BrokenSourceRecheck must not adopt around it.
      def operator_pinned_base_url?(key)
        operator_overrides(key).key?("base_url")
      end

      private

      # base_url precedence, lowest to highest: manifest, a domain adopted from
      # the upstream catalog after it healed a broken source, the operator's
      # config/sources.yml override, an explicit caller override (probes).
      def source_config(entry, base_url_override: nil)
        adopted = adopted_base_url(entry.key)
        config = { "base_url" => adopted || entry.base_url }.merge(operator_overrides(entry.key))
        config["base_url"] = base_url_override if base_url_override

        # Shipped Referer headers point at the source's own domain. When the
        # effective domain moved (adoption or a probe override), the stale
        # Referer would fail hotlink checks on the new host.
        effective = base_url_override || adopted
        if effective && config["base_url"] == effective
          config["headers"] = rewrite_referer(config["headers"], effective)
        end
        config
      end

      def rewrite_referer(headers, base_url)
        return headers unless headers.is_a?(Hash) && headers["Referer"]

        headers.merge("Referer" => "#{base_url.chomp("/")}/")
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
