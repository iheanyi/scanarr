require "test_helper"
require "json"
require "uri"

class BatotoAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = normalize_uri(build_uri(path_or_url, params))
      key = "GET #{uri}"
      # Try exact match first, then without query string
      body = @mapping[key]
      unless body
        fallback = uri.dup
        fallback.query = nil
        body = @mapping["GET #{fallback}"]
      end
      unless body
        # Try matching just the path
        @mapping.each do |k, v|
          if key.include?(URI(k.sub("GET ", "")).path)
            body = v
            break
          end
        end
      end
      body ||= ""
      Response.new(status: body.empty? ? 404 : 200, body: body, headers: {}, url: uri.to_s)
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

    def normalize_uri(uri)
      return uri if uri.query.nil?

      params = URI.decode_www_form(uri.query).sort_by { |pair| pair.join }
      uri.query = URI.encode_www_form(params)
      uri
    end
  end

  def setup
    @base_url = "https://bato.to"
    @series_id = "81514"
    @series_slug = "81514-one-piece"
    @chapter_id = "1193305"
    @fixtures = {
      "GET #{@base_url}/v3x-search" => search_fixture,
      "GET #{@base_url}/title/#{@series_slug}" => series_fixture,
      "GET #{@base_url}/title/#{@series_slug}?start=-1" => chapters_fixture,
      "GET #{@base_url}/chapter/#{@chapter_id}" => pages_fixture_js_var,
      "GET #{@base_url}/v3x-search?sort=update&page=1" => search_fixture,
      "GET #{@base_url}/v3x-search?sort=views_a&page=1" => search_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::Batoto::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("one piece")

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
    assert_equal @series_slug, results.first.id
    assert_equal "#{@base_url}/title/#{@series_slug}", results.first.url
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("one piece")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("one piece")

    assert_match %r{https://}, results.first.cover_url
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Batoto::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("one piece")

    assert_empty results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/title/#{@series_slug}")

    assert_equal "One Piece", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Adventure"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/title/#{@series_slug}")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/title/#{@series_slug}")

    assert_equal "Oda Eiichiro", series.author
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/title/#{@series_slug}")

    assert_not_nil series.cover_url
    assert_match %r{cover}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/title/#{@series_slug}")

    assert_not_nil series.description
    assert_includes series.description, "pirate"
  end

  def test_series_from_id
    series = @adapter.series(@series_slug)

    assert_equal "One Piece", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Batoto::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/title/99999")

    assert_nil result
  end

  # --- Chapters Tests ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/title/#{@series_slug}")

    assert_equal 3, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/title/#{@series_slug}")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_extracts_numbers
    chapters = @adapter.chapters("#{@base_url}/title/#{@series_slug}")

    numbers = chapters.map(&:number).map(&:to_f)

    assert_includes numbers, 1.0
    assert_includes numbers, 2.0
    assert_includes numbers, 3.0
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/title/#{@series_slug}")

    numbers = chapters.map { |ch| ch.number.to_f }

    assert_equal numbers.sort, numbers
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/title/#{@series_slug}")

    chapters.each do |chapter|
      assert chapter.url.start_with?("#{@base_url}/chapter/")
    end
  end

  def test_chapters_extracts_title
    chapters = @adapter.chapters("#{@base_url}/title/#{@series_slug}")

    titled_chapter = chapters.find { |ch| ch.title.present? }

    assert_not_nil titled_chapter
    assert_equal "Romance Dawn", titled_chapter.title
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Batoto::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/title/99999")

    assert_empty result
  end

  # --- Pages Tests ---

  def test_pages_returns_urls_from_js_var
    pages = @adapter.pages("#{@base_url}/chapter/#{@chapter_id}")

    assert_equal 3, pages.size
    assert_equal 1, pages.first.index
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/chapter/#{@chapter_id}")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/chapter/#{@chapter_id}")

    pages.each do |page|
      assert page.url.start_with?("https://")
      assert_match /\.(jpg|jpeg|png|webp)/i, page.url
    end
  end

  def test_pages_from_cdn_pattern
    cdn_fixtures = @fixtures.merge(
      "GET #{@base_url}/chapter/cdn-test" => pages_fixture_cdn
    )
    http = FakeHttpClient.new(mapping: cdn_fixtures, base_url: @base_url)
    adapter = Scrapers::Batoto::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/chapter/cdn-test")

    assert_equal 3, pages.size
    pages.each do |page|
      assert_match %r{https://}, page.url
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Batoto::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/chapter/99999")

    assert_empty result
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/chapter/#{@chapter_id}")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_returns_browse_results
    results = @adapter.browse(sort: "latest", page: 1)

    assert_operator results.size, :>, 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_popular
    results = @adapter.browse(sort: "popular", page: 1)

    assert_operator results.size, :>, 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  # --- Private Method Tests (via public interface) ---

  def test_normalize_series_url_from_full_url
    series = @adapter.series("#{@base_url}/title/#{@series_slug}")

    assert_not_nil series
    assert_equal "One Piece", series.title
  end

  def test_normalize_series_url_from_path
    series = @adapter.series(@series_slug)

    assert_not_nil series
    assert_equal "One Piece", series.title
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Search - Bato.To</title></head>
      <body>
        <div id="series-list">
          <div class="col">
            <a href="/title/#{@series_slug}">
              <img src="https://bato.to/media/cover-one-piece.jpg" alt="One Piece" />
            </a>
            <a href="/title/#{@series_slug}" class="item-title">One Piece</a>
          </div>
          <div class="col">
            <a href="/title/81515-one-piece-party">
              <img src="https://bato.to/media/cover-opp.jpg" alt="One Piece Party" />
            </a>
            <a href="/title/81515-one-piece-party" class="item-title">One Piece Party</a>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def series_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece - Bato.To</title></head>
      <body>
        <h3><a href="/title/#{@series_slug}">One Piece</a></h3>
        <img src="https://bato.to/media/cover-one-piece.jpg" class="shadow" alt="cover" />
        <a href="/author?name=Oda+Eiichiro">Oda Eiichiro</a>
        <span class="text-success">Ongoing</span>
        <a href="/genre/action">Action</a>
        <a href="/genre/adventure">Adventure</a>
        <a href="/genre/comedy">Comedy</a>
        <div class="limit-html">
          Gol D. Roger was known as the "Pirate King," the strongest and most
          infamous being to have sailed the Grand Line. A young pirate named
          Monkey D. Luffy sets out on his adventure to find the legendary treasure.
        </div>
        <span class="text-muted">ワンピース / One Piece</span>

        <div class="space-x-1">
          <a href="/chapter/1193307">Ch.3</a>
        </div>
        <div class="space-x-1">
          <a href="/chapter/1193306">Ch.2</a>
        </div>
        <div class="space-x-1">
          <a href="/chapter/#{@chapter_id}">Ch.1</a>
          <span>: Romance Dawn</span>
        </div>
      </body>
      </html>
    HTML
  end

  def chapters_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece - Bato.To</title></head>
      <body>
        <div class="space-x-1">
          <a href="/chapter/1193307">Ch.3</a>
        </div>
        <div class="space-x-1">
          <a href="/chapter/1193306">Ch.2</a>
        </div>
        <div class="space-x-1">
          <a href="/chapter/#{@chapter_id}">Ch.1</a>
          <span>: Romance Dawn</span>
        </div>
      </body>
      </html>
    HTML
  end

  def pages_fixture_js_var
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece Ch.1 - Bato.To</title></head>
      <body>
        <script>
          const imgHttps = ["https://k03.cdn-images.com/media/page-001.jpg","https://k03.cdn-images.com/media/page-002.jpg","https://k03.cdn-images.com/media/page-003.png"];
        </script>
        <div class="viewer-cnt">
        </div>
      </body>
      </html>
    HTML
  end

  def pages_fixture_cdn
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Chapter Reader</title></head>
      <body>
        <div class="viewer-cnt">
          <img src="https://k03.batoto-cdn.com/media/ch1/page-001.webp" />
          <img src="https://k03.batoto-cdn.com/media/ch1/page-002.webp" />
          <img src="https://k03.batoto-cdn.com/media/ch1/page-003.webp" />
        </div>
      </body>
      </html>
    HTML
  end
end
