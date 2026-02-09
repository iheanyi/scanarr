require "test_helper"

class TcbScansAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = URI(path_or_url.to_s)
      uri = URI.join(@base_url, path_or_url.to_s) if uri.host.nil?
      key = "GET #{uri}"
      body = @mapping.fetch(key, nil)
      status = body ? 200 : 404
      Response.new(status: status, body: body || "", headers: {}, url: uri.to_s)
    end
  end

  def setup
    @base_url = "https://tcbonepiecechapters.com"
    @fixtures = {
      "GET #{@base_url}/projects" => projects_fixture,
      "GET #{@base_url}/mangas/one-piece" => series_fixture,
      "GET #{@base_url}/chapters/1094/one-piece-chapter-1094" => pages_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::TcbScans::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  def test_search_returns_results
    results = @adapter.search("one piece")

    assert_equal 1, results.size
    assert_equal "One Piece", results.first.title
    assert_equal "#{@base_url}/mangas/one-piece", results.first.url
  end

  def test_search_filters_by_query
    results = @adapter.search("jujutsu")

    assert_equal 1, results.size
    assert_equal "Jujutsu Kaisen", results.first.title
  end

  def test_search_case_insensitive
    results = @adapter.search("ONE PIECE")

    assert_equal 1, results.size
    assert_equal "One Piece", results.first.title
  end

  def test_search_no_results
    results = @adapter.search("nonexistent manga")

    assert_empty results
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("one piece")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("one piece")

    assert_equal "#{@base_url}/covers/one-piece.jpg", results.first.cover_url
  end

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/mangas/one-piece")

    assert_equal "One Piece", series.title
    assert_equal "A pirate adventure story about Monkey D. Luffy.", series.description
    assert_equal "ongoing", series.status
    assert_equal "manga", series.series_type
    assert_equal "#{@base_url}/covers/one-piece-cover.jpg", series.cover_url
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/mangas/one-piece")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_returns_nil_for_not_found
    series = @adapter.series("#{@base_url}/mangas/nonexistent")

    assert_nil series
  end

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/mangas/one-piece")

    assert_equal 2, chapters.size
  end

  def test_chapters_extracts_number
    chapters = @adapter.chapters("#{@base_url}/mangas/one-piece")

    assert_equal "1094", chapters.first.number
    assert_equal "1093", chapters.last.number
  end

  def test_chapters_builds_title_with_description
    chapters = @adapter.chapters("#{@base_url}/mangas/one-piece")

    assert_equal "Chapter 1094: Five Elders", chapters.first.title
  end

  def test_chapters_builds_title_without_description
    chapters = @adapter.chapters("#{@base_url}/mangas/one-piece")

    assert_equal "Chapter 1093", chapters.last.title
  end

  def test_chapters_sets_group
    chapters = @adapter.chapters("#{@base_url}/mangas/one-piece")

    assert_equal "TCB Scans", chapters.first.group
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/mangas/one-piece")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/mangas/one-piece")

    assert_equal "#{@base_url}/chapters/1094/one-piece-chapter-1094", chapters.first.url
    assert_equal "#{@base_url}/chapters/1093/one-piece-chapter-1093", chapters.last.url
  end

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/chapters/1094/one-piece-chapter-1094")

    assert_equal 3, pages.size
    assert_equal "#{@base_url}/cdn/pages/op-1094-001.jpg", pages.first.url
    assert_equal "#{@base_url}/cdn/pages/op-1094-002.png", pages[1].url
    assert_equal "#{@base_url}/cdn/pages/op-1094-003.webp", pages[2].url
  end

  def test_pages_sets_index
    pages = @adapter.pages("#{@base_url}/chapters/1094/one-piece-chapter-1094")

    assert_equal 0, pages.first.index
    assert_equal 1, pages[1].index
    assert_equal 2, pages[2].index
  end

  def test_pages_detects_mime_type
    pages = @adapter.pages("#{@base_url}/chapters/1094/one-piece-chapter-1094")

    assert_equal "image/jpeg", pages.first.mime_type
    assert_equal "image/png", pages[1].mime_type
    assert_equal "image/webp", pages[2].mime_type
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/chapters/1094/one-piece-chapter-1094")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_does_not_support_browse
    refute @adapter.supports_browse?
  end

  private

  def projects_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Projects</title></head>
      <body>
        <div class="bg-card">
          <a href="/mangas/one-piece" class="text-white">One Piece</a>
          <img src="/covers/one-piece.jpg" alt="One Piece">
        </div>
        <div class="bg-card">
          <a href="/mangas/jujutsu-kaisen" class="text-white">Jujutsu Kaisen</a>
          <img src="/covers/jujutsu-kaisen.jpg" alt="Jujutsu Kaisen">
        </div>
        <div class="bg-card">
          <a href="/mangas/my-hero-academia" class="text-white">My Hero Academia</a>
          <img src="/covers/my-hero-academia.jpg" alt="My Hero Academia">
        </div>
      </body>
      </html>
    HTML
  end

  def series_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece</title></head>
      <body>
        <div class="order-1">
          <h1>One Piece</h1>
          <img src="/covers/one-piece-cover.jpg" alt="One Piece">
          <p>A pirate adventure story about Monkey D. Luffy.</p>
        </div>
        <div class="grid">
          <a href="/chapters/1094/one-piece-chapter-1094">
            <div class="font-bold">One Piece Chapter 1094</div>
            <span class="text-gray-500">Five Elders</span>
          </a>
          <a href="/chapters/1093/one-piece-chapter-1093">
            <div class="font-bold">One Piece Chapter 1093</div>
            <span class="text-gray-500"></span>
          </a>
        </div>
      </body>
      </html>
    HTML
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece Chapter 1094</title></head>
      <body>
        <picture>
          <img src="/cdn/pages/op-1094-001.jpg" alt="Page 1">
        </picture>
        <picture>
          <img src="/cdn/pages/op-1094-002.png" alt="Page 2">
        </picture>
        <picture>
          <img src="/cdn/pages/op-1094-003.webp" alt="Page 3">
        </picture>
      </body>
      </html>
    HTML
  end
end
