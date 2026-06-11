# frozen_string_literal: true

require "net/http"

module Sources
  # Mirrors the keiyoushi (Mihon/Tachiyomi community) extensions index into
  # upstream_sources. The feed is untrusted third-party data: every entry is
  # schema-validated here and invalid entries are skipped, never raised on.
  # This service writes catalog rows only. It never enables, disables, or
  # otherwise mutates Source records, and sources missing from a fetch keep
  # their rows (last_seen_at just goes stale) so a flaky feed cannot erase
  # local state.
  class UpstreamCatalogService
    INDEX_URL = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"
    FETCH_TIMEOUT_SECONDS = 20

    Result = Data.define(:upserted, :skipped)

    class FetchError < StandardError; end

    def initialize(payload: nil)
      @payload = payload
    end

    def call
      extensions = @payload || fetch_index
      now = Time.current
      rows = []
      skipped = 0

      Array(extensions).each do |extension|
        unless extension.is_a?(Hash) && extension["sources"].is_a?(Array)
          skipped += 1
          next
        end

        extension["sources"].each do |source|
          attrs = parse_source(source, extension, now)
          attrs ? rows << attrs : skipped += 1
        end
      end

      rows.uniq! { |row| row[:mihon_id] }
      rows.each_slice(500) do |slice|
        UpstreamSource.upsert_all(slice, unique_by: :mihon_id)
      end

      Result.new(upserted: rows.size, skipped: skipped)
    end

    private

    def parse_source(source, extension, now)
      return nil unless source.is_a?(Hash)

      mihon_id = source["id"].to_s
      name = source["name"].to_s.strip
      lang = source["lang"].to_s.strip
      return nil unless mihon_id.match?(/\A\d+\z/) && name.present? && lang.present?

      {
        mihon_id: mihon_id,
        name: name,
        lang: lang,
        base_url: valid_url(source["baseUrl"]),
        nsfw: extension["nsfw"].to_i == 1,
        extension_pkg: extension["pkg"].is_a?(String) ? extension["pkg"] : nil,
        extension_version_code: extension["code"].is_a?(Integer) ? extension["code"] : nil,
        last_seen_at: now,
        created_at: now,
        updated_at: now
      }
    end

    # The feed is third-party data. A poisoned baseUrl pointing at an internal
    # or reserved address would otherwise be stored, then adopted and probed
    # by the recovery job, turning the catalog into an SSRF vector. Literal
    # hosts are rejected here; hostnames get a DNS resolution check at
    # adoption time in BrokenSourceRecheck.
    def valid_url(value)
      uri = URI.parse(value.to_s)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
      return nil if PublicUrl.internal_host?(uri.host)

      value.to_s
    rescue URI::InvalidURIError
      nil
    end

    def fetch_index
      response = Net::HTTP.start("raw.githubusercontent.com", 443, use_ssl: true,
                                 open_timeout: FETCH_TIMEOUT_SECONDS, read_timeout: FETCH_TIMEOUT_SECONDS) do |http|
        http.get(URI(INDEX_URL).path)
      end
      raise FetchError, "keiyoushi index returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise FetchError, "keiyoushi index is not valid JSON: #{e.message}"
    end
  end
end
