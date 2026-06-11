# frozen_string_literal: true

require "resolv"

module Sources
  # Recovery probe for a broken source. Probes the current domain first; if
  # that fails and the upstream catalog knows a different domain, probes it
  # and adopts it when it works. Adoption is sticky (persisted on the source)
  # so a healed source stays on the working domain instead of flip-flopping
  # back to the dead one. Every probe is recorded as a ScraperRun so the
  # health evaluator sees the evidence.
  class BrokenSourceRecheck
    PROBE_QUERY = "one piece"

    def initialize(source, adapter_registry: Scrapers::AdapterRegistry, resolver: Resolv.method(:getaddresses))
      @source = source
      @adapter_registry = adapter_registry
      @resolver = resolver
    end

    def call
      return if probe(base_url: nil)

      upstream_url = upstream_alternative
      return unless upstream_url

      @source.update!(adopted_base_url: upstream_url) if probe(base_url: upstream_url)
    end

    private

    def probe(base_url:)
      run = ScraperRun.create!(source: @source, run_type: "recheck", status: "running", started_at: Time.current)
      adapter = @adapter_registry.for(@source, base_url: base_url)
      results = adapter.search(PROBE_QUERY)
      raise Scrapers::Errors::ScraperError, "search returned no results" if results.empty?

      run.update!(
        status: "success",
        finished_at: Time.current,
        stats_json: { "query" => PROBE_QUERY, "search_count" => results.size, "base_url" => base_url }.compact
      )
      true
    rescue StandardError => e
      run&.update!(status: "failed", finished_at: Time.current, error: "#{e.class}: #{e.message}")
      false
    end

    def upstream_alternative
      # An operator-pinned base_url outranks adoption in the registry, so a
      # successful upstream probe would heal the source while normal traffic
      # kept using the pinned domain. Respect the pin and don't probe around it.
      return nil if @adapter_registry.operator_pinned_base_url?(@source.key)

      entry = Scrapers::Manifest.entry_for(@source.key)
      return nil unless entry&.mihon_id

      upstream_url = UpstreamSource.find_by(mihon_id: entry.mihon_id)&.base_url.presence
      return nil unless upstream_url
      # Ingest only rejects internal IP literals; a poisoned hostname must be
      # caught here, where it is about to be fetched for the first time.
      return nil if PublicUrl.resolves_internal?(URI(upstream_url).host, resolver: @resolver)

      current = @source.adopted_base_url.presence || entry.base_url
      upstream_url == current ? nil : upstream_url
    end
  end
end
