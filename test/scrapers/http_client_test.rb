require "test_helper"

module Scrapers
  class HttpClientTest < ActiveSupport::TestCase
    PUBLIC_ADDR = "93.184.216.34"

    test "a public-resolving host is fetched normally" do
      stub_request(:get, "https://manga.example/feed").to_return(status: 200, body: "ok")
      client = HttpClient.new(config: { "delay_ms" => 0 }, resolver: ->(_host) { [ PUBLIC_ADDR ] })

      response = client.get("https://manga.example/feed")

      assert_equal 200, response.status
      assert_equal "ok", response.body
    end

    test "refuses a host whose every resolved address is internal at connection time" do
      client = HttpClient.new(config: {}, resolver: ->(_host) { [ "10.0.0.1" ] })

      assert_raises(Errors::InternalHostRefusedError) do
        client.get("https://rebind.example/feed")
      end
    end

    test "a host that passed the adoption-time check is still refused when it re-resolves internal" do
      answers = [ [ PUBLIC_ADDR ], [ "169.254.169.254" ] ]
      resolver = ->(_host) { answers.shift }

      refute Sources::PublicUrl.resolves_internal?("rebind.example", resolver: resolver)

      client = HttpClient.new(config: {}, resolver: resolver)
      assert_raises(Errors::InternalHostRefusedError) do
        client.get("https://rebind.example/feed")
      end
    end

    test "refuses an internal IP literal without consulting the resolver" do
      resolver_calls = 0
      counting_resolver = lambda do |_host|
        resolver_calls += 1
        []
      end
      client = HttpClient.new(config: {}, resolver: counting_resolver)

      assert_raises(Errors::InternalHostRefusedError) do
        client.get("http://127.0.0.1/feed")
      end
      assert_equal 0, resolver_calls
    end

    test "pins the resolved address while Host, SNI, and verification keep the hostname" do
      client = HttpClient.new(config: {}, resolver: ->(_host) { [ PUBLIC_ADDR ] })
      http = Net::HTTP.new("manga.example", 443, nil)

      client.send(:pin_public_address, http)

      assert_equal PUBLIC_ADDR, http.ipaddr
      assert_equal "manga.example", http.address
    end

    test "pins the first public address when resolution mixes internal and public" do
      client = HttpClient.new(config: {}, resolver: ->(_host) { [ "10.0.0.1", PUBLIC_ADDR ] })
      http = Net::HTTP.new("manga.example", 443, nil)

      client.send(:pin_public_address, http)

      assert_equal PUBLIC_ADDR, http.ipaddr
    end

    test "fails closed when a host resolves to nothing" do
      # An empty answer must refuse, not connect unpinned: Net::HTTP would
      # re-resolve at #start, reopening the rebinding window the pin closes.
      client = HttpClient.new(config: {}, resolver: ->(_host) { [] })
      http = Net::HTTP.new("nxdomain.example", 443, nil)

      assert_raises(Errors::InternalHostRefusedError) do
        client.send(:pin_public_address, http)
      end
      assert_nil http.ipaddr
    end

    test "fails closed when resolution exceeds the open timeout" do
      stalling_resolver = ->(_host) { sleep 5; [ PUBLIC_ADDR ] }
      client = HttpClient.new(config: { "open_timeout" => 0.1 }, resolver: stalling_resolver)
      http = Net::HTTP.new("slow-dns.example", 443, nil)

      assert_raises(Errors::InternalHostRefusedError) do
        client.send(:pin_public_address, http)
      end
    end

    test "leaves proxied connections to the proxy" do
      client = HttpClient.new(
        config: { "proxy_url" => "http://proxy.example:8080" },
        resolver: ->(_host) { [ "10.0.0.1" ] }
      )
      http = Net::HTTP.new("rebind.example", 443, "proxy.example", 8080)

      client.send(:pin_public_address, http)

      assert_nil http.ipaddr
    end
  end
end
