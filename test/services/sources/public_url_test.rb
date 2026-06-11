require "test_helper"

module Sources
  class PublicUrlTest < ActiveSupport::TestCase
    test "rejects noncanonical IPv4 forms that the socket layer resolves to loopback" do
      # getaddrinfo handles these numerically, no DNS involved
      assert PublicUrl.resolves_internal?("127.1")
      assert PublicUrl.resolves_internal?("2130706433")
    end

    test "rejects hostnames whose resolution is internal and allows public ones" do
      assert PublicUrl.resolves_internal?("metadata.example", resolver: ->(_h) { [ "169.254.169.254" ] })
      refute PublicUrl.resolves_internal?("manga.example", resolver: ->(_h) { [ "93.184.216.34" ] })
    end

    test "allows unresolvable hosts through" do
      refute PublicUrl.resolves_internal?("nxdomain.example", resolver: ->(_h) { [] })
    end
  end
end
