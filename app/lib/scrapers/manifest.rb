# frozen_string_literal: true

module Scrapers
  # Parse boundary for config/sources/manifest.yml, the single source of truth
  # for source identity, adapter class, and per-adapter version. Invalid
  # entries fail loudly at load time rather than surfacing as runtime errors
  # deep in scraping paths.
  class Manifest
    class InvalidManifestError < StandardError; end

    KEY_FORMAT = /\A[a-z0-9_]+\z/
    SOURCE_TYPES = %w[api html].freeze

    Entry = Data.define(
      :key,
      :name,
      :adapter_class_name,
      :version,
      :base_url,
      :source_type,
      :priority,
      :enabled,
      :dead,
      :capabilities
    ) do
      def adapter_class
        adapter_class_name.constantize
      end
    end

    class << self
      def api_version
        data.fetch("api_version")
      end

      def entries
        @entries ||= data.fetch("sources").map { |key, attrs| parse_entry(key, attrs || {}) }
      end

      def keys
        entries.map(&:key)
      end

      def entry_for(key)
        entries_by_key[key.to_s]
      end

      def reload!
        @entries = nil
        @entries_by_key = nil
        @data = nil
      end

      private

      def entries_by_key
        @entries_by_key ||= entries.index_by(&:key)
      end

      def data
        @data ||= YAML.safe_load_file(manifest_path)
      end

      def manifest_path
        Rails.root.join("config/sources/manifest.yml")
      end

      def parse_entry(key, attrs)
        validate!(key, attrs)

        Entry.new(
          key: key,
          name: attrs.fetch("name"),
          adapter_class_name: attrs.fetch("adapter"),
          version: attrs.fetch("version"),
          base_url: attrs.fetch("base_url"),
          source_type: attrs.fetch("source_type"),
          priority: attrs.fetch("priority"),
          enabled: attrs.fetch("enabled", true),
          dead: attrs.fetch("dead", false),
          capabilities: (attrs["capabilities"] || {}).deep_stringify_keys
        )
      end

      def validate!(key, attrs)
        problems = []
        problems << "key must match #{KEY_FORMAT.inspect}" unless key.match?(KEY_FORMAT)
        problems << "name is required" if attrs["name"].blank?
        problems << "adapter is required" if attrs["adapter"].blank?
        problems << "version must be an Integer >= 1" unless attrs["version"].is_a?(Integer) && attrs["version"] >= 1
        problems << "base_url must be a valid http(s) URL" unless valid_url?(attrs["base_url"])
        problems << "source_type must be one of #{SOURCE_TYPES.join(', ')}" unless SOURCE_TYPES.include?(attrs["source_type"])
        problems << "priority must be an Integer" unless attrs["priority"].is_a?(Integer)

        return if problems.empty?

        raise InvalidManifestError, "Manifest entry #{key.inspect}: #{problems.join('; ')}"
      end

      def valid_url?(value)
        uri = URI.parse(value.to_s)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
