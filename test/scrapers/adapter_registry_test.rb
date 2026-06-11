require "test_helper"

module Scrapers
  class AdapterRegistryTest < ActiveSupport::TestCase
    test "manifest base_url is the default" do
      adapter = AdapterRegistry.for("weeb_central")

      assert_equal Manifest.entry_for("weeb_central").base_url, adapter.config["base_url"]
    end

    test "an adopted base_url overrides the manifest default" do
      sources(:one).update!(adopted_base_url: "https://weebcentral.moved")

      adapter = AdapterRegistry.for("weeb_central")

      assert_equal "https://weebcentral.moved", adapter.config["base_url"]
    end

    test "an explicit caller override wins over an adopted base_url" do
      sources(:one).update!(adopted_base_url: "https://weebcentral.moved")

      adapter = AdapterRegistry.for("weeb_central", base_url: "https://probe.example")

      assert_equal "https://probe.example", adapter.config["base_url"]
    end
  end
end
