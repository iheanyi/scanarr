require "test_helper"

module Sources
  class SyncServiceTest < ActiveSupport::TestCase
    test "creates missing sources and fills metadata from the manifest" do
      result = SyncService.new.call

      assert_equal Scrapers::Manifest.keys.sort, Source.where(key: Scrapers::Manifest.keys).pluck(:key).sort

      mangadex = Source.find_by!(key: "mangadex")

      assert_equal "MangaDex", mangadex.name
      assert_equal "https://api.mangadex.org", mangadex.base_url
      assert_equal "api", mangadex.source_type
      assert_equal 10, mangadex.default_priority
      assert_equal 1, mangadex.adapter_version
      assert_includes result.created, mangadex
    end

    test "is idempotent across repeated runs" do
      SyncService.new.call
      second = SyncService.new.call

      assert_empty second.created
      assert_empty second.updated
      assert_equal Scrapers::Manifest.keys.size, second.unchanged.size
    end

    test "preserves an operator's enabled toggle on existing sources" do
      source = sources(:one)
      source.update!(enabled: false)

      SyncService.new.call

      refute source.reload.enabled
    end

    test "adapter version bump resets health probation, rate limit, and adopted URL" do
      source = sources(:one)
      source.update!(
        adapter_version: 0,
        health_status: "broken",
        rate_limited_until: 1.hour.from_now,
        adopted_base_url: "https://weebcentral.moved"
      )
      stale_streak = series_sources(:one)
      stale_streak.update!(consecutive_failures: 5)

      SyncService.new.call
      source.reload

      assert_equal Scrapers::Manifest.entry_for(source.key).version, source.adapter_version
      assert_not_nil source.adapter_version_synced_at
      assert_equal "healthy", source.health_status
      assert_nil source.rate_limited_until
      # The bump may ship a corrected domain; a stale adoption must not outrank it
      assert_nil source.adopted_base_url
      # Stale per-series streaks must not count toward post-probation health
      assert_equal 0, stale_streak.reload.consecutive_failures
    end

    test "unchanged version leaves health alone" do
      SyncService.new.call
      source = Source.find_by!(key: "weeb_central")
      source.update!(health_status: "degraded")

      SyncService.new.call

      assert_equal "degraded", source.reload.health_status
    end

    test "dead manifest entry force-disables the source and pins health to dead" do
      source = sources(:one)
      source.update!(enabled: true, health_status: "healthy", adapter_version: 1)

      SyncService.new(entries: [ entry_for(source, dead: true) ]).call
      source.reload

      refute source.enabled
      assert_equal "dead", source.health_status
    end

    test "version bump on a dead entry does not resurrect health" do
      source = sources(:one)
      source.update!(adapter_version: 1, health_status: "dead", enabled: false)

      SyncService.new(entries: [ entry_for(source, dead: true, version: 2) ]).call
      source.reload

      assert_equal 2, source.adapter_version
      assert_equal "dead", source.health_status
    end

    test "removing the dead flag resurrects health to a fresh probation" do
      source = sources(:one)
      source.update!(
        adapter_version: 1,
        health_status: "dead",
        enabled: false,
        adapter_version_synced_at: 2.weeks.ago,
        rate_limited_until: 1.hour.from_now,
        adopted_base_url: "https://weebcentral.recovered"
      )
      # Stale pre-death failures that a fresh probation must window out
      3.times do |i|
        ScraperRun.create!(
          source: source, run_type: "smoke", status: "failed",
          started_at: (i + 1).days.ago, finished_at: (i + 1).days.ago, created_at: (i + 1).days.ago
        )
      end

      SyncService.new(entries: [ entry_for(source, dead: false) ]).call
      source.reload

      assert_equal "healthy", source.health_status
      assert_nil source.rate_limited_until
      # The pre-death adoption must not outrank the manifest's domain
      assert_nil source.adopted_base_url
      # Operator agency: resurrection does not auto-re-enable
      refute source.enabled
      # The probation is real: stale evidence is windowed out, so the
      # evaluator does not immediately flip the source back to broken
      assert_equal "healthy", HealthEvaluator.new(source).derived_status
    end

    test "never writes capabilities so operator overrides and manifest removals both work" do
      source = sources(:mature)
      source.update!(capabilities: { "mature_content" => false, "operator_flag" => true })

      SyncService.new.call
      source.reload

      # Operator-owned column is untouched; manifest capabilities are
      # consulted at runtime instead of being synced into the row
      refute source.capabilities["mature_content"]
      assert source.capabilities["operator_flag"]
      refute_predicate source, :mature_content?
    end

    private

    def entry_for(source, dead:, version: 1)
      Scrapers::Manifest::Entry.new(
        key: source.key,
        name: source.name,
        adapter_class_name: "Scrapers::WeebCentral::Adapter",
        version: version,
        base_url: source.base_url,
        source_type: source.source_type,
        priority: source.default_priority || 20,
        enabled: true,
        dead: dead,
        capabilities: {},
        mihon_id: nil
      )
    end
  end
end
