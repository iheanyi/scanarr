require "test_helper"

class SourceMigrationDiscoveryServiceTest < ActiveSupport::TestCase
  class GoodAdapter
    def search(_query)
      [
        ResultTypes::SearchResult.new(
          id: "one-piece",
          title: "One Piece",
          url: "https://good-source.example/one-piece",
          chapter_count: 120
        )
      ]
    end
  end

  class FailingAdapter
    def search(_query)
      raise StandardError, "adapter exploded"
    end
  end

  class TimeoutAdapter
    def search(_query)
      raise Timeout::Error, "execution expired"
    end
  end

  def test_call_collects_source_errors_while_returning_candidates
    series_record = series(:one)
    from_source = sources(:one)

    good_source = Source.create!(
      key: "good_source_for_discovery",
      name: "Good Source",
      slug: "good-source-for-discovery",
      base_url: "https://good-source.example",
      enabled: true
    )

    failing_source = Source.create!(
      key: "failing_source_for_discovery",
      name: "Failing Source",
      slug: "failing-source-for-discovery",
      base_url: "https://failing-source.example",
      enabled: true
    )

    missing_source = Source.create!(
      key: "missing_adapter_for_discovery",
      name: "Missing Adapter Source",
      slug: "missing-adapter-source-for-discovery",
      base_url: "https://missing-adapter.example",
      enabled: true
    )

    registered_proc = lambda do |source_key|
      source_key != missing_source.key
    end

    for_proc = lambda do |source|
      case source.key
      when good_source.key
        GoodAdapter.new
      when failing_source.key
        FailingAdapter.new
      else
        raise Scrapers::AdapterRegistry::UnknownSourceError, "unexpected source #{source.key}"
      end
    end

    original_registered = Scrapers::AdapterRegistry.method(:registered?)
    original_for = Scrapers::AdapterRegistry.method(:for)
    result = nil

    begin
      Scrapers::AdapterRegistry.define_singleton_method(:registered?) { |source_key| registered_proc.call(source_key) }
      Scrapers::AdapterRegistry.define_singleton_method(:for) { |source| for_proc.call(source) }
      result = SourceMigrationDiscoveryService.new(series: series_record, from_source: from_source).call
    ensure
      Scrapers::AdapterRegistry.define_singleton_method(:registered?, original_registered)
      Scrapers::AdapterRegistry.define_singleton_method(:for, original_for)
    end

    assert_equal 1, result.candidates.size
    assert_equal good_source.id, result.candidates.first.source.id
    assert_equal 120, result.candidates.first.chapter_count

    assert_includes result.errors, "#{missing_source.name}: adapter not implemented"
    assert result.errors.any? { |error| error.include?("#{failing_source.name}: adapter exploded") }
  end

  def test_call_reports_timeout_errors_cleanly
    series_record = series(:one)
    from_source = sources(:one)

    timeout_source = Source.create!(
      key: "timeout_source_for_discovery",
      name: "Timeout Source",
      slug: "timeout-source-for-discovery",
      base_url: "https://timeout-source.example",
      enabled: true
    )

    original_registered = Scrapers::AdapterRegistry.method(:registered?)
    original_for = Scrapers::AdapterRegistry.method(:for)
    result = nil

    begin
      Scrapers::AdapterRegistry.define_singleton_method(:registered?) do |source_key|
        source_key == timeout_source.key
      end
      Scrapers::AdapterRegistry.define_singleton_method(:for) do |source|
        raise Scrapers::AdapterRegistry::UnknownSourceError, "unexpected source #{source.key}" unless source.key == timeout_source.key

        TimeoutAdapter.new
      end
      result = SourceMigrationDiscoveryService.new(series: series_record, from_source: from_source).call
    ensure
      Scrapers::AdapterRegistry.define_singleton_method(:registered?, original_registered)
      Scrapers::AdapterRegistry.define_singleton_method(:for, original_for)
    end

    assert_empty result.candidates
    assert_includes result.errors, "#{timeout_source.name}: search timed out after #{SourceMigrationDiscoveryService::SEARCH_TIMEOUT_SECONDS}s"
  end

  test "a selected source limits discovery and still excludes unavailable sources" do
    target = sources(:two)
    target.update!(enabled: true)
    with_registry_stub(:registered?, true) do
      with_registry_stub(:for, ->(source) { assert_equal target.id, source.id; GoodAdapter.new }) do
        result = discover(source_id: target.id)

        assert_equal [ target.id ], result.candidates.map { |candidate| candidate.source.id }
        target.update!(health_status: :broken)

        unavailable = discover(source_id: target.id)

        assert_empty unavailable.candidates
        assert_equal 1, unavailable.errors.size
        assert_includes unavailable.errors.first, "no longer available"
      end
    end
  end

  test "a selected provider with no installed adapter reports its unavailable integration" do
    with_registry_stub(:registered?, false) do
      result = discover(source_id: sources(:mature).id)

      assert_empty result.candidates
      assert_equal [ "Manhwa18: adapter not implemented" ], result.errors
    end
  end

  test "exact titles rank before larger unrelated matches" do
    exact = sources(:two)
    exact.update!(enabled: true)
    partial = sources(:mature)
    adapter = Object.new
    adapter.define_singleton_method(:search) do |_query|
      [ ResultTypes::SearchResult.new(id: "spinoff", title: "One Piece Special", url: "https://example.com/spinoff", chapter_count: 999) ]
    end
    with_registry_stub(:registered?, true) do
      with_registry_stub(:for, ->(source) { source.id == exact.id ? GoodAdapter.new : adapter }) do
        assert_equal [ exact.id, partial.id ], discover.candidates.map { |candidate| candidate.source.id }
      end
    end
  end

  test "selected provider exposes distinct editions with covers without fetching their chapters" do
    results = [
      ResultTypes::SearchResult.new(id: "spinoff", title: "One Piece Special", url: "https://example.com/special", chapter_count: 999),
      ResultTypes::SearchResult.new(id: "original", title: "One Piece", url: "https://example.com/original", cover_url: "https://example.com/original.jpg", chapter_count: 120),
      ResultTypes::SearchResult.new(id: "color", title: "One Piece", url: "https://example.com/color", cover_url: "https://example.com/color.jpg"),
      ResultTypes::SearchResult.new(id: "color", title: "One Piece", url: "https://example.com/color-duplicate"),
      ResultTypes::SearchResult.new(id: "unrelated", title: "Naruto", url: "https://example.com/naruto")
    ]
    adapter = Object.new
    adapter.define_singleton_method(:search) { |_query| results }
    chapter_requests = []
    adapter.define_singleton_method(:chapters) { |url| chapter_requests << url; [] }
    with_registry_stub(:registered?, true) do
      with_registry_stub(:for, adapter) do
        candidates = discover(source_id: sources(:mature).id).candidates

        assert_equal %w[original color spinoff], candidates.map { |candidate| candidate.result.id }
        assert_equal [ 120, nil, 999 ], candidates.map(&:chapter_count)
        assert_equal "https://example.com/color.jpg", candidates.second.result.cover_url
        assert_empty chapter_requests
        assert candidates.none?(&:linked)
        assert_equal candidates.map { |candidate| candidate.result.id }, discover.candidates.map { |candidate| candidate.result.id }
      end
    end
  end

  test "selected provider returns every distinct plausible edition after ranking all results" do
    results = 6.times.map do |index|
      ResultTypes::SearchResult.new(id: "edition-#{index}", title: "One Piece Special #{index}", url: "https://example.com/#{index}")
    end
    results << ResultTypes::SearchResult.new(id: "exact", title: "One Piece", url: "https://example.com/exact")
    adapter = Object.new
    adapter.define_singleton_method(:search) { |_query| results }
    with_registry_stub(:registered?, true) do
      with_registry_stub(:for, adapter) do
        candidates = discover(source_id: sources(:mature).id).candidates

        assert_equal 7, candidates.size
        assert_equal "exact", candidates.first.result.id
        assert_equal 7, candidates.map { |candidate| candidate.result.id }.uniq.size
      end
    end
  end

  test "linked candidates use the existing mapping even when search would find another title" do
    target = sources(:two)
    target.update!(enabled: true)
    series(:one).series_sources.create!(source: target, source_series_id: "existing-edition")
    adapter = Object.new
    adapter.define_singleton_method(:series) do |id|
      raise "wrong mapping" unless id == "existing-edition"
      ResultTypes::Series.new(id: id, title: "One Piece", url: "https://example.com/existing-edition")
    end
    adapter.define_singleton_method(:chapters) { |_url| [ :chapter ] }
    with_registry_stub(:registered?, true) do
      with_registry_stub(:for, adapter) do
        candidate = discover(source_id: target.id).candidates.sole

        assert candidate.linked
        assert_equal "existing-edition", candidate.result.id
        assert_equal "https://example.com/existing-edition", candidate.result.url
        assert_nil candidate.chapter_count
      end
    end
  end

  test "a single matching title never triggers an eager chapter lookup" do
    adapter = GoodAdapter.new
    adapter.define_singleton_method(:search) do |_query|
      [ ResultTypes::SearchResult.new(id: "one-piece", title: "One Piece", url: "https://example.com/one-piece") ]
    end
    chapter_requests = []
    adapter.define_singleton_method(:chapters) { |url| chapter_requests << url; [] }
    with_registry_stub(:registered?, true) do
      with_registry_stub(:for, adapter) do
        candidate = discover(source_id: sources(:mature).id).candidates.sole

        assert_equal "One Piece", candidate.result.title
        assert_nil candidate.chapter_count
        assert_empty chapter_requests
      end
    end
  end

  test "rate limits are not described as bot challenges" do
    adapter = Object.new
    adapter.define_singleton_method(:search) { |_query| raise Scrapers::Errors::RateLimitError }
    with_registry_stub(:registered?, true) do
      with_registry_stub(:for, adapter) do
        result = discover(source_id: sources(:mature).id)

        assert_equal [ "Manhwa18: rate limited; try again later" ], result.errors
      end
    end
  end

  test "one deadline bounds queued sources and retains completed candidates" do
    slow = Object.new
    slow.define_singleton_method(:search) { |_query| sleep 2 }
    6.times do |index|
      Source.create!(key: "slow_#{index}", name: "Slow #{index}", slug: "slow-#{index}", enabled: true)
    end
    fast_source_id = sources(:mature).id
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    with_discovery_timeout(0.1) do
      with_registry_stub(:registered?, true) do
        with_registry_stub(:for, ->(source) { source.id == fast_source_id ? GoodAdapter.new : slow }) do
          result = discover

          assert_equal [ sources(:mature).id ], result.candidates.map { |candidate| candidate.source.id }
          assert_equal 6, result.errors.size
          assert result.errors.all? { |error| error.include?("discovery timed out") }
        end
      end
    end

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at, :<, 1
  end

  private

  def discover(source_id: nil)
    SourceMigrationDiscoveryService.new(series: series(:one), from_source: sources(:one), source_id: source_id).call
  end

  def with_registry_stub(method_name, replacement)
    original = Scrapers::AdapterRegistry.method(method_name)
    Scrapers::AdapterRegistry.define_singleton_method(method_name) do |*arguments|
      replacement.respond_to?(:call) ? replacement.call(*arguments) : replacement
    end
    yield
  ensure
    Scrapers::AdapterRegistry.define_singleton_method(method_name, original)
  end

  def with_discovery_timeout(seconds)
    original = SourceMigrationDiscoveryService::DISCOVERY_TIMEOUT_SECONDS
    SourceMigrationDiscoveryService.send(:remove_const, :DISCOVERY_TIMEOUT_SECONDS)
    SourceMigrationDiscoveryService.const_set(:DISCOVERY_TIMEOUT_SECONDS, seconds)
    yield
  ensure
    SourceMigrationDiscoveryService.send(:remove_const, :DISCOVERY_TIMEOUT_SECONDS)
    SourceMigrationDiscoveryService.const_set(:DISCOVERY_TIMEOUT_SECONDS, original)
  end
end
