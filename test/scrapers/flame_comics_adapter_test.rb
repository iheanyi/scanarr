require "test_helper"
require "json"
require "uri"

class FlameComicsAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = build_uri(path_or_url, params)
      key = "GET #{uri}"

      # Try exact match first, then without query params
      if @mapping.key?(key)
        body = @mapping[key]
        Response.new(status: 200, body: body, headers: { "content-type" => "application/json" }, url: uri.to_s)
      else
        fallback = uri.dup
        fallback.query = nil
        fallback_key = "GET #{fallback}"
        if @mapping.key?(fallback_key)
          body = @mapping[fallback_key]
          Response.new(status: 200, body: body, headers: { "content-type" => "application/json" }, url: uri.to_s)
        else
          Response.new(status: 404, body: "", headers: {}, url: uri.to_s)
        end
      end
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
    @base_url = "https://flamecomics.xyz"
    @build_id = "test-build-id-123"
    @series_id = 42

    @fixtures = {
      # Homepage for build ID extraction
      "GET #{@base_url}" => homepage_fixture,
      # Browse endpoint
      "GET #{@base_url}/_next/data/#{@build_id}/browse.json" => browse_fixture,
      # Series + chapters endpoint
      "GET #{@base_url}/_next/data/#{@build_id}/series/#{@series_id}.json" => series_fixture,
      # Pages endpoint
      "GET #{@base_url}/_next/data/#{@build_id}/series/#{@series_id}/abc123token.json" => pages_fixture
    }

    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::FlameComics::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search ---

  def test_search_returns_results
    results = @adapter.search("Solo Leveling")

    assert_equal 1, results.size
    assert_equal "Solo Leveling", results.first.title
    assert_equal "42", results.first.id
  end

  def test_search_is_case_insensitive
    results = @adapter.search("solo leveling")

    assert_equal 1, results.size
    assert_equal "Solo Leveling", results.first.title
  end

  def test_search_matches_alt_titles
    results = @adapter.search("Na Honjaman")

    assert_equal 1, results.size
    assert_equal "Solo Leveling", results.first.title
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("Solo")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_returns_empty_for_no_match
    results = @adapter.search("xyznonexistent")

    assert_empty results
  end

  def test_search_builds_cover_url
    results = @adapter.search("Solo Leveling")

    assert_equal "https://cdn.flamecomics.xyz/uploads/images/series/42/cover.jpg?1705334400", results.first.cover_url
  end

  # --- Series ---

  def test_series_parses_details
    series = @adapter.series(@series_id.to_s)

    assert_equal "Solo Leveling", series.title
    assert_equal "42", series.id
    assert_equal "Chugong", series.author
    assert_equal "Dubu", series.artist
    assert_equal "ongoing", series.status
    assert_equal "manhwa", series.series_type
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Fantasy"
    assert_includes series.alt_titles, "Na Honjaman Level-Up"
  end

  def test_series_strips_html_from_description
    series = @adapter.series(@series_id.to_s)

    assert_equal "A great manhwa about leveling up.", series.description
  end

  def test_series_from_url
    series = @adapter.series("#{@base_url}/series/#{@series_id}")

    assert_equal "Solo Leveling", series.title
  end

  def test_series_returns_series_struct
    series = @adapter.series(@series_id.to_s)

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_builds_cover_url
    series = @adapter.series(@series_id.to_s)

    assert_equal "https://cdn.flamecomics.xyz/uploads/images/series/42/cover.jpg?1705334400", series.cover_url
  end

  def test_series_builds_url
    series = @adapter.series(@series_id.to_s)

    assert_equal "#{@base_url}/series/42", series.url
  end

  # --- Chapters ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/series/#{@series_id}")

    assert_equal 2, chapters.size
  end

  def test_chapters_parses_details
    chapters = @adapter.chapters(@series_id.to_s)

    ch = chapters.find { |c| c.number == "179" }

    assert_not_nil ch
    assert_equal "abc123token", ch.id
    assert_equal "The Final Battle", ch.title
    assert_equal "en", ch.language
    assert_equal "Flame Comics", ch.group
  end

  def test_chapters_formats_whole_numbers
    chapters = @adapter.chapters(@series_id.to_s)

    numbers = chapters.map(&:number)

    assert_includes numbers, "179"
    assert_includes numbers, "178"
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters(@series_id.to_s)

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_builds_url
    chapters = @adapter.chapters(@series_id.to_s)

    ch = chapters.find { |c| c.number == "179" }

    assert_equal "#{@base_url}/series/42/abc123token", ch.url
  end

  def test_chapters_parses_published_at
    chapters = @adapter.chapters(@series_id.to_s)

    ch = chapters.find { |c| c.number == "179" }

    assert_not_nil ch.published_at
    assert_match(/2024-01-15/, ch.published_at)
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters(@series_id.to_s)

    numbers = chapters.map { |c| c.number.to_f }

    assert_equal numbers.sort, numbers
  end

  # --- Pages ---

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/series/#{@series_id}/abc123token")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/series/#{@series_id}/abc123token")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_sorted_by_index
    pages = @adapter.pages("#{@base_url}/series/#{@series_id}/abc123token")

    indices = pages.map(&:index)

    assert_equal [ 0, 1, 2 ], indices
  end

  def test_pages_builds_cdn_urls
    pages = @adapter.pages("#{@base_url}/series/#{@series_id}/abc123token")

    assert_match %r{cdn\.flamecomics\.xyz/uploads/images/series/42/abc123token/001\.webp}, pages.first.url
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/series/#{@series_id}/abc123token")

    assert_equal "image/webp", pages.first.mime_type
  end

  # --- Browse ---

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_sort_options
    assert_equal %w[latest popular alphabetical], @adapter.browse_sort_options
  end

  def test_browse_latest
    results = @adapter.browse(sort: "latest", page: 1, limit: 10)

    assert_equal 2, results.size
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_popular_sorts_by_views
    results = @adapter.browse(sort: "popular", page: 1, limit: 10)

    assert_equal 2, results.size
    # "Solo Leveling" has 50000 views, "Tower of God" has 30000
    assert_equal "Solo Leveling", results.first.title
    assert_equal "Tower of God", results.last.title
  end

  def test_browse_alphabetical
    results = @adapter.browse(sort: "alphabetical", page: 1, limit: 10)

    assert_equal 2, results.size
    assert_equal "Solo Leveling", results.first.title
    assert_equal "Tower of God", results.last.title
  end

  def test_browse_pagination
    results = @adapter.browse(sort: "latest", page: 1, limit: 1)

    assert_equal 1, results.size
  end

  def test_browse_returns_status
    results = @adapter.browse(sort: "popular", page: 1, limit: 10)

    completed_result = results.find { |r| r.title == "Solo Leveling" }

    assert_equal "completed", completed_result.status
  end

  private

  def homepage_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Flame Comics</title></head>
      <body>
        <script id="__NEXT_DATA__" type="application/json">{"buildId":"#{@build_id}","props":{}}</script>
      </body>
      </html>
    HTML
  end

  def browse_fixture
    {
      "pageProps" => {
        "series" => [
          {
            "title" => "Solo Leveling",
            "altTitles" => [ "Na Honjaman Level-Up" ],
            "description" => "<p>A great manhwa about leveling up.</p>",
            "cover" => "cover.jpg",
            "type" => "Manhwa",
            "tags" => [ "Action", "Fantasy" ],
            "author" => [ "Chugong" ],
            "artist" => [ "Dubu" ],
            "status" => "Completed",
            "series_id" => 42,
            "last_edit" => 1705334400,
            "views" => 50000
          },
          {
            "title" => "Tower of God",
            "altTitles" => [ "Sin-ui Tap" ],
            "description" => "A story about climbing a tower.",
            "cover" => "tog-cover.jpg",
            "type" => "Manhwa",
            "tags" => [ "Action", "Adventure" ],
            "author" => [ "SIU" ],
            "artist" => [ "SIU" ],
            "status" => "Ongoing",
            "series_id" => 99,
            "last_edit" => 1705420800,
            "views" => 30000
          }
        ]
      }
    }.to_json
  end

  def series_fixture
    {
      "pageProps" => {
        "series" => {
          "title" => "Solo Leveling",
          "altTitles" => [ "Na Honjaman Level-Up" ],
          "description" => "<p>A great manhwa about leveling up.</p>",
          "cover" => "cover.jpg",
          "type" => "Manhwa",
          "tags" => [ "Action", "Fantasy" ],
          "author" => [ "Chugong" ],
          "artist" => [ "Dubu" ],
          "status" => "Ongoing",
          "series_id" => 42,
          "last_edit" => 1705334400
        },
        "chapters" => [
          {
            "chapter" => 179.0,
            "title" => "The Final Battle",
            "release_date" => 1705334400,
            "series_id" => 42,
            "token" => "abc123token"
          },
          {
            "chapter" => 178.0,
            "title" => "Preparation",
            "release_date" => 1705248000,
            "series_id" => 42,
            "token" => "def456token"
          }
        ]
      }
    }.to_json
  end

  def pages_fixture
    {
      "pageProps" => {
        "chapter" => {
          "release_date" => 1705334400,
          "series_id" => 42,
          "token" => "abc123token",
          "images" => {
            "0" => { "name" => "001.webp" },
            "1" => { "name" => "002.webp" },
            "2" => { "name" => "003.webp" }
          }
        }
      }
    }.to_json
  end
end
