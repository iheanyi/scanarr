require "test_helper"

class AdapterCoverageTest < ActiveSupport::TestCase
  def test_every_registered_adapter_has_a_dedicated_test_file
    missing = Scrapers::AdapterRegistry.registered_keys.reject do |key|
      Rails.root.join("test/scrapers/#{key}_adapter_test.rb").exist?
    end

    assert_empty missing, "Missing dedicated adapter tests for: #{missing.join(', ')}"
  end
end
