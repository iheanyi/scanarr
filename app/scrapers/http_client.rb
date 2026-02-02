require "faraday"
require "faraday/retry"
require "uri"

class HttpClient
  Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

  def initialize(config:)
    @config = config
    @last_request_at = nil
    @connection = Faraday.new(url: @config["base_url"], proxy: proxy_url) do |conn|
      conn.request :url_encoded
      conn.request :retry, retry_options
      conn.options.open_timeout = @config.fetch("open_timeout", 10)
      conn.options.timeout = @config.fetch("read_timeout", 20)
      conn.adapter Faraday.default_adapter
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

module Scrapers
  HttpClient = ::HttpClient
end
