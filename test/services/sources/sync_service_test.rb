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

    test "adapter version bump resets health probation and rate limit" do
      source = sources(:one)
      source.update!(
        adapter_version: 0,
        health_status: "broken",
        rate_limited_until: 1.hour.from_now
      )

      SyncService.new.call
      source.reload

      assert_equal 1, source.adapter_version
      assert_not_nil source.adapter_version_synced_at
      assert_equal "healthy", source.health_status
      assert_nil source.rate_limited_until
    end

    test "unchanged version leaves health alone" do
      SyncService.new.call
      source = Source.find_by!(key: "weeb_central")
      source.update!(health_status: "degraded")

      SyncService.new.call

      assert_equal "degraded", source.reload.health_status
    end

    test "dead manifest entry force-disables the source" do
      dead_entry = Scrapers::Manifest::Entry.new(
        key: "weeb_central",
        name: "Weeb Central",
        adapter_class_name: "Scrapers::WeebCentral::Adapter",
        version: 2,
        base_url: "https://weebcentral.com",
        source_type: "html",
        priority: 20,
        enabled: true,
        dead: true,
        capabilities: {},
        mihon_id: nil
      )
      source = sources(:one)
      source.update!(enabled: true)

      SyncService.new(entries: [ dead_entry ]).call

      refute source.reload.enabled
    end

    test "merges manifest capabilities over existing ones without dropping operator keys" do
      source = sources(:mature)
      source.update!(capabilities: { "mature_content" => false, "operator_flag" => true })

      SyncService.new.call
      source.reload

      assert source.capabilities["mature_content"]
      assert source.capabilities["operator_flag"]
    end
  end
end
