require "test_helper"

module Sources
  class BrokenSourceRecheckTest < ActiveSupport::TestCase
    class FakeAdapter
      def initialize(results_by_base_url)
        @results_by_base_url = results_by_base_url
      end

      attr_accessor :base_url

      def search(_query, filters: {})
        outcome = @results_by_base_url.fetch(@base_url)
        raise Scrapers::Errors::SourceUnavailableError, "down" if outcome == :down

        outcome
      end
    end

    class FakeRegistry
      def initialize(adapter)
        @adapter = adapter
      end

      def for(_source, base_url: nil)
        @adapter.base_url = base_url
        @adapter
      end
    end

    OK_RESULT = [ Scrapers::ResultTypes::SearchResult.new(id: "1", title: "One Piece", url: "https://x/1") ].freeze
    PUBLIC_RESOLVER = ->(_host) { [ "93.184.216.34" ] }

    setup do
      @source = sources(:one) # weeb_central
      @source.update!(health_status: "broken", health_changed_at: 1.day.ago)
    end

    test "successful probe of the current domain records success and adopts nothing" do
      registry = FakeRegistry.new(FakeAdapter.new(nil => OK_RESULT))

      BrokenSourceRecheck.new(@source, adapter_registry: registry).call

      assert_equal [ "success" ], @source.scraper_runs.where(run_type: "recheck").pluck(:status)
      assert_nil @source.reload.adopted_base_url
    end

    test "failed probe with no upstream alternative records one failed run" do
      registry = FakeRegistry.new(FakeAdapter.new(nil => :down))

      BrokenSourceRecheck.new(@source, adapter_registry: registry).call

      assert_equal [ "failed" ], @source.scraper_runs.where(run_type: "recheck").pluck(:status)
      assert_nil @source.reload.adopted_base_url
    end

    test "adopts the upstream domain when the current one fails and upstream works" do
      UpstreamSource.create!(
        mihon_id: "2131019126180322627", name: "Weeb Central", lang: "en",
        base_url: "https://weebcentral.moved", last_seen_at: Time.current
      )
      registry = FakeRegistry.new(FakeAdapter.new(nil => :down, "https://weebcentral.moved" => OK_RESULT))

      BrokenSourceRecheck.new(@source, adapter_registry: registry, resolver: PUBLIC_RESOLVER).call

      assert_equal %w[failed success], @source.scraper_runs.where(run_type: "recheck").order(:created_at).pluck(:status)
      assert_equal "https://weebcentral.moved", @source.reload.adopted_base_url
    end

    test "refuses an upstream domain that resolves to an internal address" do
      UpstreamSource.create!(
        mihon_id: "2131019126180322627", name: "Weeb Central", lang: "en",
        base_url: "https://weebcentral.moved", last_seen_at: Time.current
      )
      registry = FakeRegistry.new(FakeAdapter.new(nil => :down, "https://weebcentral.moved" => OK_RESULT))

      internal_resolver = ->(_host) { [ "169.254.169.254" ] }
      BrokenSourceRecheck.new(@source, adapter_registry: registry, resolver: internal_resolver).call

      # Only the current-domain probe ran; the poisoned domain was never fetched
      assert_equal [ "failed" ], @source.scraper_runs.where(run_type: "recheck").pluck(:status)
      assert_nil @source.reload.adopted_base_url
    end

    test "does not adopt when the upstream domain also fails" do
      UpstreamSource.create!(
        mihon_id: "2131019126180322627", name: "Weeb Central", lang: "en",
        base_url: "https://weebcentral.moved", last_seen_at: Time.current
      )
      registry = FakeRegistry.new(FakeAdapter.new(nil => :down, "https://weebcentral.moved" => :down))

      BrokenSourceRecheck.new(@source, adapter_registry: registry, resolver: PUBLIC_RESOLVER).call

      assert_equal %w[failed failed], @source.scraper_runs.where(run_type: "recheck").order(:created_at).pluck(:status)
      assert_nil @source.reload.adopted_base_url
    end

    test "empty search results count as a failed probe" do
      registry = FakeRegistry.new(FakeAdapter.new(nil => []))

      BrokenSourceRecheck.new(@source, adapter_registry: registry).call

      assert_equal [ "failed" ], @source.scraper_runs.where(run_type: "recheck").pluck(:status)
    end

    test "skips the upstream domain when it matches the current one" do
      UpstreamSource.create!(
        mihon_id: "2131019126180322627", name: "Weeb Central", lang: "en",
        base_url: "https://weebcentral.com", last_seen_at: Time.current
      )
      registry = FakeRegistry.new(FakeAdapter.new(nil => :down))

      BrokenSourceRecheck.new(@source, adapter_registry: registry).call

      assert_equal [ "failed" ], @source.scraper_runs.where(run_type: "recheck").pluck(:status)
    end
  end
end
