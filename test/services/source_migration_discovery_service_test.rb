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

  def test_call_collects_errors_sequentially_while_returning_candidates
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
end
