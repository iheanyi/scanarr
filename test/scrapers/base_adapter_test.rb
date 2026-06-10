require "test_helper"

module Scrapers
  class BaseAdapterTest < ActiveSupport::TestCase
    def test_default_http_client_uses_scrapers_http_client
      adapter = BaseAdapter.new(config: { "base_url" => "https://example.test" })

      assert_instance_of HttpClient, adapter.http
    end
  end
end
