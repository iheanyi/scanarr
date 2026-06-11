require "test_helper"

class AdapterCoverageTest < ActiveSupport::TestCase
  # Stands in for Scrapers::HttpClient, recording every requested URL and
  # answering with an empty 200 so adapters return without parsing anything.
  class RecordingHttpClient
    attr_reader :urls

    def initialize(base_url:)
      @base_url = base_url
      @urls = []
    end

    def get(path_or_url, **)
      record(path_or_url)
    end

    def post(path_or_url, **)
      record(path_or_url)
    end

    private

    def record(path_or_url)
      uri = URI(path_or_url.to_s)
      uri = URI.join(@base_url, path_or_url.to_s) if uri.host.nil?
      @urls << uri.to_s
      Scrapers::HttpClient::Response.new(status: 200, body: "{}", headers: {}, url: uri.to_s)
    end
  end

  def test_every_registered_adapter_has_a_dedicated_test_file
    missing = Scrapers::AdapterRegistry.registered_keys.reject do |key|
      Rails.root.join("test/scrapers/#{key}_adapter_test.rb").exist?
    end

    assert_empty missing, "Missing dedicated adapter tests for: #{missing.join(', ')}"
  end

  def test_manifest_parses_and_validates
    assert_operator Scrapers::Manifest.entries.size, :>=, 1
    assert_equal 1, Scrapers::Manifest.api_version
  end

  def test_every_adapter_directory_is_registered_in_the_manifest
    adapter_dirs = Rails.root.glob("app/lib/scrapers/*/adapter.rb").map { |path| path.parent.basename.to_s }
    unregistered = adapter_dirs - Scrapers::Manifest.keys

    assert_empty unregistered,
      "Adapters with no manifest entry (add them to config/sources/manifest.yml): #{unregistered.join(', ')}"
  end

  def test_every_manifest_entry_resolves_to_a_base_adapter_subclass
    Scrapers::Manifest.entries.each do |entry|
      klass = entry.adapter_class

      assert_operator klass, :<, Scrapers::BaseAdapter,
        "#{entry.key}: #{entry.adapter_class_name} must inherit from Scrapers::BaseAdapter"
    end
  end

  def test_every_adapter_honors_the_browse_contract
    Scrapers::AdapterRegistry.registered_keys.each do |key|
      adapter = Scrapers::AdapterRegistry.adapter_for_key(key)
      next unless adapter.supports_browse?

      sorts = adapter.browse_sort_options

      assert_kind_of Array, sorts, "#{key}: browse_sort_options must return an array"
      assert_not_empty sorts, "#{key}: browse adapter must declare at least one sort option"
      assert(sorts.all? { |sort| sort.is_a?(String) }, "#{key}: browse sort options must be strings")
      assert_operator adapter.browse_page_size, :>, 0, "#{key}: browse_page_size must be positive"
    end
  end

  def test_filter_options_are_label_value_pairs
    Scrapers::AdapterRegistry.registered_keys.each do |key|
      adapter = Scrapers::AdapterRegistry.adapter_for_key(key)

      [ adapter.search_filter_options, adapter.browse_filter_options ].each do |options|
        options.each do |group, pairs|
          assert_kind_of Array, pairs, "#{key}: filter group #{group} must be an array"
          pairs.each do |pair|
            assert_equal 2, Array(pair).size, "#{key}: filter group #{group} entries must be [label, value] pairs"
          end
        end
      end
    end
  end

  # Operator base_url pins and moved-domain adoption only work when adapters
  # build requests from config["base_url"] instead of their class constant.
  def test_every_adapter_requests_only_the_configured_base_url
    override = "https://moved-domain.example"

    Scrapers::Manifest.entries.each do |entry|
      http = RecordingHttpClient.new(base_url: override)
      adapter = entry.adapter_class.new(config: { "base_url" => override }, http: http)
      adapter.supports_search? ? adapter.search("naruto") : adapter.browse

      hosts = http.urls.map { |url| URI(url).host }.uniq

      assert_not_empty hosts, "#{entry.key}: adapter issued no requests"
      assert_equal [ "moved-domain.example" ], hosts,
        "#{entry.key}: requested #{hosts.join(', ')} despite the base_url override"
    end
  end

  def test_all_registered_adapters_implement_filter_capability_contract
    Scrapers::AdapterRegistry.registered_keys.each do |key|
      adapter = Scrapers::AdapterRegistry.adapter_for_key(key)

      assert_respond_to adapter, :supports_search?, "#{key} adapter must expose supports_search?"
      assert_respond_to adapter, :supports_browse?, "#{key} adapter must expose supports_browse?"
      assert_respond_to adapter, :supports_server_side_filters?, "#{key} adapter must expose supports_server_side_filters?"
      assert_respond_to adapter, :search_filter_options, "#{key} adapter must expose search_filter_options"
      assert_respond_to adapter, :browse_filter_options, "#{key} adapter must expose browse_filter_options"

      assert_includes [ true, false ], adapter.supports_search?, "#{key} adapter supports_search? must return boolean"
      assert_includes [ true, false ], adapter.supports_browse?, "#{key} adapter supports_browse? must return boolean"
      assert_includes [ true, false ], adapter.supports_server_side_filters?, "#{key} adapter supports_server_side_filters? must return boolean"
      assert_kind_of Hash, adapter.search_filter_options, "#{key} adapter search_filter_options must return a hash"
      assert_kind_of Hash, adapter.browse_filter_options, "#{key} adapter browse_filter_options must return a hash"
    end
  end
end
