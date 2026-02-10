require "test_helper"
require "json"
require "uri"

class ComickAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = normalize_uri(build_uri(path_or_url, params))
      key = "GET #{uri}"
      fallback = uri.dup
      fallback.query = nil
      body = @mapping[key] || @mapping.fetch("GET #{fallback}")
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

    def normalize_uri(uri)
      return uri if uri.query.nil?

      params = URI.decode_www_form(uri.query).sort_by { |pair| pair.join }
      uri.query = URI.encode_www_form(params)
      uri
    end
  end

  def setup
    @base_url = "https://comick.live"
    @slug = "one-piece"
    @chapter_hid = "abc123"
    @fixtures = {
      "GET #{@base_url}/api/search" => search_fixture,
      "GET #{@base_url}/comic/#{@slug}" => series_fixture,
      "GET #{@base_url}/api/comics/#{@slug}/chapter-list" => chapters_fixture,
      "GET #{@base_url}/comic/#{@slug}/#{@chapter_hid}-chapter-1094-en" => pages_fixture,
      "GET #{@base_url}/api/comics/top" => browse_popular_fixture,
      "GET #{@base_url}/api/chapters/latest" => browse_latest_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::Comick::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  def test_search_returns_results
    results = @adapter.search("one piece")

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
    assert_equal "one-piece", results.first.id
    assert_equal "#{@base_url}/comic/one-piece", results.first.url
    assert_equal "https://meo.comick.pictures/cover-one-piece.jpg", results.first.cover_url
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("one piece")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_series_parses_details
    series = @adapter.series(@slug)

    assert_equal "One Piece", series.title
    assert_equal "one-piece", series.id
    assert_equal "Oda Eiichiro", series.author
    assert_equal "Oda Eiichiro", series.artist
    assert_equal "ongoing", series.status
    assert_equal "manga", series.series_type
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Adventure"
    assert_includes series.alt_titles, "ワンピース"
    assert_equal "A pirate adventure story.", series.description
  end

  def test_series_from_url
    series = @adapter.series("#{@base_url}/comic/#{@slug}")

    assert_equal "One Piece", series.title
  end

  def test_series_country_mapping
    series = @adapter.series(@slug)

    assert_equal "manga", series.series_type
  end

  def test_chapters_returns_list
    chapters = @adapter.chapters(@slug)

    assert_equal 2, chapters.size
    assert_equal "1094", chapters.first.number
    assert_equal "abc123", chapters.first.id
    assert_equal "en", chapters.first.language
    assert_equal "TCB Scans", chapters.first.group
  end

  def test_chapters_builds_title
    chapters = @adapter.chapters(@slug)

    assert_equal "Vol. 105 Ch. 1094 - The Five Elders", chapters.first.title
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters(@slug)

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_builds_url
    chapters = @adapter.chapters(@slug)

    assert_equal "#{@base_url}/comic/one-piece/abc123-chapter-1094-en", chapters.first.url
  end

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/comic/#{@slug}/#{@chapter_hid}-chapter-1094-en")

    assert_equal 3, pages.size
    assert_equal 1, pages.first.index
    assert_match %r{meo\.comick\.pictures}, pages.first.url
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/comic/#{@slug}/#{@chapter_hid}-chapter-1094-en")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_popular
    results = @adapter.browse(sort: "popular", page: 1, limit: 10)

    assert_equal 2, results.size
    assert_kind_of ResultTypes::BrowseResult, results.first
    assert_equal "One Piece", results.first.title
  end

  def test_browse_latest
    results = @adapter.browse(sort: "latest", page: 1, limit: 10)

    assert_equal 2, results.size
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_extract_slug_from_various_formats
    adapter = Scrapers::Comick::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    # These test the private extract_slug method indirectly via series()
    # Test with plain slug
    series = adapter.series("one-piece")

    assert_equal "One Piece", series.title

    # Test with full URL
    series = adapter.series("https://comick.live/comic/one-piece")

    assert_equal "One Piece", series.title
  end

  private

  def search_fixture
    [
      {
        "slug" => "one-piece",
        "title" => "One Piece",
        "default_thumbnail" => "https://meo.comick.pictures/cover-one-piece.jpg"
      },
      {
        "slug" => "one-piece-party",
        "title" => "One Piece Party",
        "default_thumbnail" => "https://meo.comick.pictures/cover-one-piece-party.jpg"
      }
    ].to_json
  end

  def series_fixture
    comic_data = {
      "title" => "One Piece",
      "slug" => "one-piece",
      "default_thumbnail" => "https://meo.comick.pictures/cover-one-piece.jpg",
      "status" => 1,
      "translation_completed" => false,
      "authors" => [ { "name" => "Oda Eiichiro" } ],
      "artists" => [ { "name" => "Oda Eiichiro" } ],
      "desc" => "<p>A pirate adventure story.</p>",
      "content_rating" => "safe",
      "country" => "jp",
      "md_comic_md_genres" => [
        { "md_genres" => { "name" => "Action" } },
        { "md_genres" => { "name" => "Adventure" } }
      ],
      "md_titles" => [
        { "title" => "ワンピース" },
        { "title" => "One Piece" }
      ]
    }

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece</title></head>
      <body>
        <script id="comic-data" type="application/json">#{comic_data.to_json}</script>
      </body>
      </html>
    HTML
  end

  def chapters_fixture
    {
      "data" => [
        {
          "hid" => "abc123",
          "chap" => "1094",
          "vol" => "105",
          "lang" => "en",
          "title" => "The Five Elders",
          "created_at" => "2024-01-15T12:00:00.000000Z",
          "group_name" => [ "TCB Scans" ]
        },
        {
          "hid" => "def456",
          "chap" => "1093",
          "vol" => "105",
          "lang" => "en",
          "title" => "Luffy vs Kizaru",
          "created_at" => "2024-01-08T12:00:00.000000Z",
          "group_name" => [ "TCB Scans" ]
        }
      ],
      "pagination" => {
        "current_page" => 1,
        "last_page" => 1
      }
    }.to_json
  end

  def pages_fixture
    chapter_data = {
      "chapter" => {
        "images" => [
          { "url" => "https://meo.comick.pictures/page-001.jpg" },
          { "url" => "https://meo.comick.pictures/page-002.jpg" },
          { "url" => "https://meo.comick.pictures/page-003.jpg" }
        ]
      }
    }

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Chapter 1094</title></head>
      <body>
        <script id="sv-data" type="application/json">#{chapter_data.to_json}</script>
      </body>
      </html>
    HTML
  end

  def browse_popular_fixture
    {
      "data" => [
        {
          "slug" => "one-piece",
          "title" => "One Piece",
          "default_thumbnail" => "https://meo.comick.pictures/cover-one-piece.jpg"
        },
        {
          "slug" => "solo-leveling",
          "title" => "Solo Leveling",
          "default_thumbnail" => "https://meo.comick.pictures/cover-solo-leveling.jpg"
        }
      ]
    }.to_json
  end

  def browse_latest_fixture
    {
      "data" => [
        {
          "slug" => "jujutsu-kaisen",
          "title" => "Jujutsu Kaisen",
          "default_thumbnail" => "https://meo.comick.pictures/cover-jjk.jpg"
        },
        {
          "slug" => "chainsaw-man",
          "title" => "Chainsaw Man",
          "default_thumbnail" => "https://meo.comick.pictures/cover-csm.jpg"
        }
      ]
    }.to_json
  end
end
