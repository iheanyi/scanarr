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

    test "effective_base_url reflects the full precedence chain" do
      assert_equal Manifest.entry_for("weeb_central").base_url, AdapterRegistry.effective_base_url("weeb_central")

      sources(:one).update!(adopted_base_url: "https://weebcentral.moved")

      assert_equal "https://weebcentral.moved", AdapterRegistry.effective_base_url("weeb_central")
      assert_nil AdapterRegistry.effective_base_url("not_a_source")
    end

    test "an adopted domain rewrites a shipped Referer header to the new host" do
      Source.create!(
        key: "asura_scans", name: "Asura Scans",
        base_url: "https://asuracomic.net", adopted_base_url: "https://asura.moved"
      )

      adapter = AdapterRegistry.for("asura_scans")

      assert_equal "https://asura.moved", adapter.config["base_url"]
      assert_equal "https://asura.moved/", adapter.config["headers"]["Referer"]
      # Other shipped headers survive the rewrite
      assert_equal "ScanarrScraper/0.1", adapter.config["headers"]["User-Agent"]
    end
  end
end
