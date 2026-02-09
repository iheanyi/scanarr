require "test_helper"
require "json"
require "uri"

class MangaBuddyAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://mangabuddy.com"
    @series_slug = "123-one-piece"
    @chapter_slug = "one-piece-chapter-1"
    @fixtures = {
      "GET #{@base_url}/search" => search_fixture,
      "GET #{@base_url}/manga/#{@series_slug}" => series_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/chapters" => chapters_api_fixture,
      "GET #{@base_url}/chapter/#{@chapter_slug}" => pages_fixture_main_server,
      "GET #{@base_url}/search?page=1&q=one+piece" => search_fixture,
      "GET #{@base_url}/search?page=1&sort=views" => search_fixture,
      "GET #{@base_url}/search?page=1&sort=updated_at" => search_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = MangaBuddy::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("one piece")

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("one piece")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("one piece")

    assert_not_nil results.first.cover_url
    assert_match %r{https://}, results.first.cover_url
  end

  def test_search_includes_url
    results = @adapter.search("one piece")

    assert results.first.url.start_with?("#{@base_url}/manga/")
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaBuddy::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("one piece")

    assert_equal [], results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}")

    assert_equal "One Piece", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Adventure"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}")

    assert_equal "Oda Eiichiro", series.author
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}")

    assert_not_nil series.cover_url
    assert_match %r{https://}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}")

    assert_not_nil series.description
    assert_includes series.description, "pirate"
  end

  def test_series_extracts_alt_titles
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}")

    assert_not_empty series.alt_titles
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "One Piece", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaBuddy::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/manga/99999-nonexistent")

    assert_nil result
  end

  # --- Chapters Tests ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}")

    assert_equal 3, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_extracts_numbers
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}")

    numbers = chapters.map(&:number).map(&:to_f)
    assert_includes numbers, 1.0
    assert_includes numbers, 2.0
    assert_includes numbers, 3.0
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}")

    numbers = chapters.map { |ch| ch.number.to_f }
    assert_equal numbers.sort, numbers
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}")

    chapters.each do |chapter|
      assert chapter.url.start_with?(@base_url)
    end
  end

  def test_chapters_extracts_title
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}")

    titled_chapter = chapters.find { |ch| ch.title.present? }
    assert_not_nil titled_chapter
    assert_equal "Romance Dawn", titled_chapter.title
  end

  def test_chapters_extracts_published_at
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}")

    dated_chapter = chapters.find { |ch| ch.published_at.present? }
    assert_not_nil dated_chapter
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaBuddy::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/manga/99999-nonexistent")

    assert_equal [], result
  end

  # --- Pages Tests ---

  def test_pages_returns_urls_from_main_server
    pages = @adapter.pages("#{@base_url}/chapter/#{@chapter_slug}")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/chapter/#{@chapter_slug}")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/chapter/#{@chapter_slug}")

    pages.each do |page|
      assert page.url.start_with?("https://")
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/chapter/#{@chapter_slug}")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_from_chapimages_full_url
    full_url_fixtures = @fixtures.merge(
      "GET #{@base_url}/chapter/full-url-test" => pages_fixture_full_urls
    )
    http = FakeHttpClient.new(mapping: full_url_fixtures, base_url: @base_url)
    adapter = MangaBuddy::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/chapter/full-url-test")

    assert_equal 3, pages.size
    pages.each do |page|
      assert page.url.start_with?("https://")
    end
  end

  def test_pages_from_html_img_fallback
    html_fixtures = @fixtures.merge(
      "GET #{@base_url}/chapter/html-test" => pages_fixture_html_imgs
    )
    http = FakeHttpClient.new(mapping: html_fixtures, base_url: @base_url)
    adapter = MangaBuddy::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/chapter/html-test")

    assert_equal 3, pages.size
    pages.each do |page|
      assert_match %r{https://}, page.url
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaBuddy::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/chapter/99999")

    assert_equal [], result
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert @adapter.supports_browse?
  end

  def test_browse_returns_browse_results
    results = @adapter.browse(sort: "latest", page: 1)

    assert results.size > 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_popular
    results = @adapter.browse(sort: "popular", page: 1)

    assert results.size > 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  # --- URL Normalization Tests ---

  def test_normalize_series_url_from_full_url
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}")

    assert_not_nil series
    assert_equal "One Piece", series.title
  end

  def test_normalize_series_url_from_slug
    series = @adapter.series(@series_slug)

    assert_not_nil series
    assert_equal "One Piece", series.title
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Search - MangaBuddy</title></head>
      <body>
        <div class="book-detailed-item">
          <a href="/manga/#{@series_slug}" title="One Piece">
            <img data-src="https://cdn.mangabuddy.com/covers/one-piece.jpg" />
          </a>
          <div class="summary">A boy sets out to become the pirate king.</div>
          <div class="genres"><a href="/genre/action">Action</a><a href="/genre/adventure">Adventure</a></div>
        </div>
        <div class="book-detailed-item">
          <a href="/manga/456-one-piece-party" title="One Piece Party">
            <img data-src="https://cdn.mangabuddy.com/covers/one-piece-party.jpg" />
          </a>
          <div class="summary">A spin-off comedy.</div>
        </div>
      </body>
      </html>
    HTML
  end

  def series_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece - MangaBuddy</title></head>
      <body>
        <div class="detail">
          <h1>One Piece</h1>
          <h2>ワンピース; Wan Pīsu</h2>
          <div class="meta">
            <p><strong>Authors</strong><a href="/author/oda-eiichiro">Oda Eiichiro</a></p>
            <p><strong>Status</strong><a href="/status/ongoing">Ongoing</a></p>
            <p><strong>Genres</strong><a href="/genre/action">Action</a><a href="/genre/adventure">Adventure</a><a href="/genre/comedy">Comedy</a></p>
          </div>
        </div>
        <div id="cover">
          <img data-src="https://cdn.mangabuddy.com/covers/one-piece.jpg" />
        </div>
        <div class="summary">
          <div class="content">
            Gol D. Roger was known as the "Pirate King." A young pirate named
            Monkey D. Luffy sets out on his adventure to find the legendary treasure.
          </div>
        </div>

        <script>
          var bookId = 123;
          var bookSlug = "one-piece";
        </script>

        <ul id="chapter-list">
          <li>
            <a href="/manga/#{@series_slug}/chapter-3"><span class="chapter-title">Chapter 3</span></a>
            <span class="chapter-update">Jan 15, 2024</span>
          </li>
          <li>
            <a href="/manga/#{@series_slug}/chapter-2"><span class="chapter-title">Chapter 2</span></a>
            <span class="chapter-update">Jan 10, 2024</span>
          </li>
          <li>
            <a href="/manga/#{@series_slug}/chapter-1"><span class="chapter-title">Chapter 1: Romance Dawn</span></a>
            <span class="chapter-update">Jan 05, 2024</span>
          </li>
        </ul>
      </body>
      </html>
    HTML
  end

  def chapters_api_fixture
    <<~HTML
      <ul id="chapter-list">
        <li>
          <a href="/manga/#{@series_slug}/chapter-3"><span class="chapter-title">Chapter 3</span></a>
          <span class="chapter-update">Jan 15, 2024</span>
        </li>
        <li>
          <a href="/manga/#{@series_slug}/chapter-2"><span class="chapter-title">Chapter 2</span></a>
          <span class="chapter-update">Jan 10, 2024</span>
        </li>
        <li>
          <a href="/manga/#{@series_slug}/chapter-1"><span class="chapter-title">Chapter 1: Romance Dawn</span></a>
          <span class="chapter-update">Jan 05, 2024</span>
        </li>
      </ul>
    HTML
  end

  def pages_fixture_main_server
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece Chapter 1 - MangaBuddy</title></head>
      <body>
        <script>
          var mainServer = "https://cdn.mangabuddy.com";
          var chapImages = '/uploads/one-piece/ch1/001.jpg,/uploads/one-piece/ch1/002.jpg,/uploads/one-piece/ch1/003.jpg';
        </script>
        <div id="chapter-images"></div>
      </body>
      </html>
    HTML
  end

  def pages_fixture_full_urls
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Chapter Reader</title></head>
      <body>
        <script>
          var chapImages = 'https://cdn1.mangabuddy.com/uploads/ch1/001.jpg,https://cdn1.mangabuddy.com/uploads/ch1/002.jpg,https://cdn1.mangabuddy.com/uploads/ch1/003.png';
        </script>
        <div id="chapter-images"></div>
      </body>
      </html>
    HTML
  end

  def pages_fixture_html_imgs
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Chapter Reader</title></head>
      <body>
        <div id="chapter-images">
          <img data-src="https://cdn.mangabuddy.com/uploads/ch1/001.jpg" />
          <img data-src="https://cdn.mangabuddy.com/uploads/ch1/002.webp" />
          <img data-src="https://cdn.mangabuddy.com/uploads/ch1/003.png" />
        </div>
      </body>
      </html>
    HTML
  end
end
