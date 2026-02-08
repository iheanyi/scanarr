ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "view_component/test_helpers"
require "components/component_test_case"
require "vcr"
require "webmock/minitest"
require "support/query_counter"
require "test_helpers/session_test_helper"

VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.ignore_localhost = true
  config.allow_http_connections_when_no_cassette = false
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    include QueryCounter
  end
end

module ActionDispatch
  class IntegrationTest
    include SessionTestHelper

    setup do
      @test_user = users(:admin)
      sign_in_as(@test_user)
    end

    def api_key_header(user = nil)
      user ||= @test_user
      { "X-Api-Key" => user.api_key }
    end
  end
end
