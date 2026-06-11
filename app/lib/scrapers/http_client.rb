require "faraday"
require "faraday/retry"
require "uri"

module Scrapers
  class HttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(config:, resolver: Sources::PublicUrl::SYSTEM_RESOLVER)
      @config = config
      @resolver = resolver
      @last_request_at = nil
      @connection = Faraday.new(url: @config["base_url"], proxy: proxy_url) do |conn|
        conn.request :url_encoded
        conn.request :retry, retry_options
        conn.options.open_timeout = @config.fetch("open_timeout", 10)
        conn.options.timeout = @config.fetch("read_timeout", 20)
        conn.adapter Faraday.default_adapter do |http|
          pin_public_address(http)
        end
      end
    end

    def get(path_or_url, headers: {}, params: {})
      url = build_url(path_or_url)
      with_rate_limit do
        response = @connection.get(url) do |req|
          req.headers.update(request_headers(headers))
          params.each { |k, v| req.params[k] = v } unless params.empty?
        end
        Response.new(
          status: response.status,
          body: response.body,
          headers: response.headers.to_h,
          url: response.env.url.to_s
        )
      end
    end

    def post(path_or_url, headers: {}, params: {}, body: {})
      url = build_url(path_or_url)
      with_rate_limit do
        response = @connection.post(url) do |req|
          req.headers.update(request_headers(headers))
          params.each { |k, v| req.params[k] = v } unless params.empty?
          req.body = body unless body.empty?
        end
        Response.new(
          status: response.status,
          body: response.body,
          headers: response.headers.to_h,
          url: response.env.url.to_s
        )
      end
    end

    private

    # Adoption-time guards (Sources::PublicUrl) classify a hostname before
    # the fetch, but Net::HTTP re-resolves at connect, so a split-horizon
    # name can answer public for the guard and internal for the socket.
    # Net::HTTP#ipaddr= closes that race: the TCP connection goes to the
    # address resolved here, while the Host header, TLS SNI, and certificate
    # verification stay keyed to #address (the original hostname).
    def pin_public_address(http)
      return if http.proxy?

      host = http.address
      raise Errors::InternalHostRefusedError, "refusing connection to internal host #{host}" if Sources::PublicUrl.internal_host?(host)

      addresses = @resolver.call(host)
      return if addresses.empty?

      address = addresses.find { |candidate| !Sources::PublicUrl.internal_address?(candidate) }
      raise Errors::InternalHostRefusedError, "#{host} resolves only to internal addresses" unless address

      http.ipaddr = address
    end

    def build_url(path_or_url)
      uri = URI(path_or_url.to_s)
      if uri.host.nil? && @config["base_url"]
        URI.join(@config["base_url"], path_or_url.to_s).to_s
      else
        uri.to_s
      end
    end

    def request_headers(extra)
      base = @config.fetch("headers", {})
      base.merge(extra)
    end

    def proxy_url
      proxy = @config["proxy_url"].to_s.strip
      proxy.empty? ? nil : proxy
    end

    def retry_options
      {
        max: @config.fetch("max_retries", 2),
        interval: 0.5,
        interval_randomness: 0.3,
        backoff_factor: 2,
        exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
      }
    end

    def with_rate_limit
      delay_ms = @config.fetch("delay_ms", 300)
      if @last_request_at
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_at) * 1000
        sleep((delay_ms - elapsed) / 1000.0) if elapsed < delay_ms
      end
      result = yield
      @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result
    end
  end
end

HttpClient = Scrapers::HttpClient unless defined?(::HttpClient)
