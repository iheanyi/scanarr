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
      def initialize(adapter, pinned: false)
        @adapter = adapter
        @pinned = pinned
      end

      def for(_source, base_url: nil)
        @adapter.base_url = base_url
        @adapter
      end

      def operator_pinned_base_url?(_key)
        @pinned
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

    test "a successful probe heals the source and un-stales its series via the evaluator" do
      stale = series_sources(:one)
      stale.update!(consecutive_failures: 12)
      registry = FakeRegistry.new(FakeAdapter.new(nil => OK_RESULT))

      # Mirror the sweep: probe, then evaluate
      BrokenSourceRecheck.new(@source, adapter_registry: registry).call
      HealthEvaluator.new(@source.reload).call

      assert_equal "healthy", @source.reload.health_status
      assert_equal 0, stale.reload.consecutive_failures
    end

    test "failed probe with no upstream alternative records one failed run" do
      stale = series_sources(:one)
      stale.update!(consecutive_failures: 12)
      registry = FakeRegistry.new(FakeAdapter.new(nil => :down))

      BrokenSourceRecheck.new(@source, adapter_registry: registry).call
      HealthEvaluator.new(@source.reload).call

      assert_equal [ "failed" ], @source.scraper_runs.where(run_type: "recheck").pluck(:status)
      assert_nil @source.reload.adopted_base_url
      # No recovery, no reset
      assert_equal 12, stale.reload.consecutive_failures
    end

    test "adopts the upstream domain when the current one fails and upstream works" do
      UpstreamSource.create!(
        mihon_id: "2131019126180322627", name: "Weeb Central", lang: "en",
        base_url: "https://weebcentral.moved", last_seen_at: Time.current
      )
      registry = FakeRegistry.new(FakeAdapter.new(nil => :down, "https://weebcentral.moved" => OK_RESULT))
      chapter = series(:one).chapters.create!(
        chapter_number: "1", language: "en", source: @source,
        source_url: "https://weebcentral.com/chapters/1"
      )
      foreign_chapter = series(:one).chapters.create!(
        chapter_number: "2", language: "en", source: @source,
        source_url: "https://elsewhere.example/chapters/2"
      )

      BrokenSourceRecheck.new(@source, adapter_registry: registry, resolver: PUBLIC_RESOLVER).call

      assert_equal %w[failed success], @source.scraper_runs.where(run_type: "recheck").order(:created_at).pluck(:status)
      assert_equal "https://weebcentral.moved", @source.reload.adopted_base_url
      # Stored URLs on the dead domain follow the adoption; others are untouched
      assert_equal "https://weebcentral.moved/chapters/1", chapter.reload.source_url
      assert_equal "https://elsewhere.example/chapters/2", foreign_chapter.reload.source_url
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

    test "does not probe the upstream domain when an operator pinned base_url" do
      UpstreamSource.create!(
        mihon_id: "2131019126180322627", name: "Weeb Central", lang: "en",
        base_url: "https://weebcentral.moved", last_seen_at: Time.current
      )
      registry = FakeRegistry.new(FakeAdapter.new(nil => :down, "https://weebcentral.moved" => OK_RESULT), pinned: true)

      BrokenSourceRecheck.new(@source, adapter_registry: registry, resolver: PUBLIC_RESOLVER).call

      # A success on the unpinned domain would heal health while real traffic
      # kept failing on the pin; only the current-domain probe may run
      assert_equal [ "failed" ], @source.scraper_runs.where(run_type: "recheck").pluck(:status)
      assert_nil @source.reload.adopted_base_url
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
