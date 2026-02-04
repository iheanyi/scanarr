ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "view_component/test_helpers"
require "components/component_test_case"
require "vcr"
require "webmock/minitest"

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
  end
end

module ActionDispatch
  class IntegrationTest
    # HTTP Basic Auth helper for tests
    def http_basic_auth_header(username = "scanarr", password = "ilovemanga")
      { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
    end

    # Override request methods to automatically include auth
    def get(path, **options)
      options[:headers] = http_basic_auth_header.merge(options[:headers] || {})
      super
    end

    def post(path, **options)
      options[:headers] = http_basic_auth_header.merge(options[:headers] || {})
      super
    end

    def patch(path, **options)
      options[:headers] = http_basic_auth_header.merge(options[:headers] || {})
      super
    end

    def delete(path, **options)
      options[:headers] = http_basic_auth_header.merge(options[:headers] || {})
      super
    end

    def follow_redirect!(**options)
      options[:headers] = http_basic_auth_header.merge(options[:headers] || {})
      super
    end
  end
end
