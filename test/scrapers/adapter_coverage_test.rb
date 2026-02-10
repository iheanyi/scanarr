require "test_helper"

class AdapterCoverageTest < ActiveSupport::TestCase
  def test_every_registered_adapter_has_a_dedicated_test_file
    missing = Scrapers::AdapterRegistry.registered_keys.reject do |key|
      Rails.root.join("test/scrapers/#{key}_adapter_test.rb").exist?
    end

    assert_empty missing, "Missing dedicated adapter tests for: #{missing.join(', ')}"
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
