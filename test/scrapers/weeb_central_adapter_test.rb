require "test_helper"
require "uri"

class WeebCentralAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = build_uri(path_or_url, params)
      body = @mapping.fetch("GET #{uri}")
      Response.new(status: 200, body: body, headers: {}, url: uri.to_s)
    end

    def post(path_or_url, params: {}, headers: {}, body: {})
      uri = build_uri(path_or_url, params)
      body = @mapping.fetch("POST #{uri}")
      Response.new(status: 200, body: body, headers: {}, url: uri.to_s)
    end

    private

    def build_uri(path_or_url, params)
      uri = URI(path_or_url.to_s)
      uri = URI.join(@base_url, path_or_url.to_s) if uri.host.nil?
      unless params.empty?
        current = URI.decode_www_form(String(uri.query))
        uri.query = URI.encode_www_form(current + params.to_a)
      end
      uri
    end
  end

  def setup
    @base_url = "https://weebcentral.com"
    @fixtures = {
      "POST #{@base_url}/search/simple?location=main" => fixture("search.html"),
      "GET #{@base_url}/series/01ABCDEF1234567890/foo-series" => fixture("series.html"),
      "GET #{@base_url}/series/01ABCDEF1234567890/foo-series/chapters?page=2" => fixture("chapters_page2.html"),
      "GET #{@base_url}/chapters/01CHAPTER0001" => fixture("chapter.html"),
      "GET #{@base_url}/chapters/01CHAPTER0001/images?is_prev=False&current_page=1&reading_style=long_strip" => fixture("chapter_images.html")
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @config = { "base_url" => @base_url }
    @adapter = WeebCentral::Adapter.new(config: @config, http: @http)
  end

  def test_search_returns_results
    results = @adapter.search("foo")
    assert_equal 2, results.size
    assert_equal "Foo Series", results.first.title
    assert_match %r{/series/01ABCDEF1234567890/}, results.first.url
  end

  def test_series_parses_metadata
    series = @adapter.series("#{@base_url}/series/01ABCDEF1234567890/foo-series")
    assert_equal "Foo Series", series.title
    assert_equal "A description of the series.", series.description
  end

  def test_chapters_handles_show_more
    chapters = @adapter.chapters("#{@base_url}/series/01ABCDEF1234567890/foo-series")
    assert_equal 3, chapters.size
    assert_equal "Chapter 1", chapters.first.title
    assert_equal "1", chapters.first.number
  end

  def test_pages_filters_non_content_images
    pages = @adapter.pages("#{@base_url}/chapters/01CHAPTER0001")
    assert_equal 2, pages.size
    assert_match %r{/manga/}, pages.first.url
  end

  private

  def fixture(name)
    File.read(Rails.root.join("test/fixtures/weeb_central", name))
  end
end
