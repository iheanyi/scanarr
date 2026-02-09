require "test_helper"
require "json"
require "uri"

class MangaKakalotAdapterTest < ActiveSupport::TestCase
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
      body = @mapping[key] || @mapping["GET #{fallback}"]
      return Response.new(status: 404, body: "", headers: {}, url: uri.to_s) unless body

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
    @base_url = "https://www.mangakakalot.gg"
    @slug = "one-piece"
    @chapter_slug = "chapter-1094"

    @fixtures = {
      "GET #{@base_url}/search/story/one_piece" => search_fixture,
      "GET #{@base_url}/manga/#{@slug}" => series_fixture,
      "GET #{@base_url}/api/manga/#{@slug}/chapters" => chapters_fixture,
      "GET #{@base_url}/manga/#{@slug}/#{@chapter_slug}" => pages_fixture,
      "GET #{@base_url}/manga-list/latest-manga" => browse_latest_fixture,
      "GET #{@base_url}/manga-list/hot-manga" => browse_popular_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = MangaKakalot::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # -- Search --

  def test_search_returns_results
    results = @adapter.search("one piece")

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
    assert_equal "one-piece", results.first.id
    assert_equal "#{@base_url}/manga/one-piece", results.first.url
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("one piece")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("one piece")

    assert_equal "https://cdn.mangakakalot.gg/cover/one-piece.jpg", results.first.cover_url
  end

  def test_search_normalizes_query
    # The adapter should normalize "one piece" to "one_piece" for the URL
    results = @adapter.search("one piece")

    assert_equal 2, results.size
  end

  def test_search_returns_empty_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaKakalot::Adapter.new(config: { "base_url" => @base_url }, http: http)

    results = adapter.search("nonexistent")

    assert_equal [], results
  end

  # -- Query Normalization --

  def test_normalize_query_lowercases
    # Test indirectly by checking the adapter doesn't error with uppercase
    results = @adapter.search("One Piece")
    assert_equal 2, results.size
  end

  # -- Series --

  def test_series_parses_details
    series = @adapter.series(@slug)

    assert_equal "One Piece", series.title
    assert_equal "one-piece", series.id
    assert_equal "Oda Eiichiro", series.author
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Adventure"
    assert_equal "A pirate adventure story.", series.description
  end

  def test_series_returns_series_struct
    series = @adapter.series(@slug)

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_from_full_url
    series = @adapter.series("#{@base_url}/manga/#{@slug}")

    assert_equal "One Piece", series.title
  end

  def test_series_cover_url
    series = @adapter.series(@slug)

    assert_equal "https://cdn.mangakakalot.gg/cover/one-piece.jpg", series.cover_url
  end

  def test_series_alt_titles
    series = @adapter.series(@slug)

    assert_includes series.alt_titles, "ワンピース"
  end

  def test_series_detects_type
    series = @adapter.series(@slug)

    assert_equal "manga", series.series_type
  end

  def test_series_returns_nil_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaKakalot::Adapter.new(config: { "base_url" => @base_url }, http: http)

    assert_nil adapter.series("nonexistent")
  end

  # -- Chapters --

  def test_chapters_returns_list
    chapters = @adapter.chapters(@slug)

    assert_equal 2, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters(@slug)

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_parses_number
    chapters = @adapter.chapters(@slug)

    numbers = chapters.map(&:number)
    assert_includes numbers, "1093"
    assert_includes numbers, "1094"
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters(@slug)

    assert_equal "1093", chapters.first.number
    assert_equal "1094", chapters.last.number
  end

  def test_chapters_builds_url
    chapters = @adapter.chapters(@slug)
    ch = chapters.find { |c| c.number == "1094" }

    assert_equal "#{@base_url}/manga/one-piece/chapter-1094", ch.url
  end

  def test_chapters_parses_title
    chapters = @adapter.chapters(@slug)
    ch = chapters.find { |c| c.number == "1094" }

    assert_equal "Five Elders", ch.title
  end

  def test_chapters_parses_published_at
    chapters = @adapter.chapters(@slug)
    ch = chapters.find { |c| c.number == "1094" }

    assert_kind_of Time, ch.published_at
  end

  def test_chapters_returns_empty_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaKakalot::Adapter.new(config: { "base_url" => @base_url }, http: http)

    assert_equal [], adapter.chapters("nonexistent")
  end

  # -- Pages --

  def test_pages_extracts_from_js_variables
    pages = @adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_equal 3, pages.size
    assert_equal 1, pages.first.index
    assert_equal "https://cdn1.mangakakalot.gg/path/to/page1.jpg", pages.first.url
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_guesses_mime_type
    pages = @adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_equal "image/jpeg", pages.first.mime_type
  end

  def test_pages_fallback_to_img_tags
    fallback_fixtures = {
      "GET #{@base_url}/manga/#{@slug}/#{@chapter_slug}" => pages_fallback_fixture
    }
    http = FakeHttpClient.new(mapping: fallback_fixtures, base_url: @base_url)
    adapter = MangaKakalot::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_equal 2, pages.size
    assert_equal "https://cdn.mangakakalot.gg/fallback/page1.jpg", pages.first.url
  end

  def test_pages_returns_empty_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaKakalot::Adapter.new(config: { "base_url" => @base_url }, http: http)

    assert_equal [], adapter.pages("#{@base_url}/manga/foo/chapter-1")
  end

  # -- Browse --

  def test_supports_browse
    assert @adapter.supports_browse?
  end

  def test_browse_latest
    results = @adapter.browse(sort: "latest", page: 1, limit: 20)

    assert_equal 2, results.size
    assert_kind_of ResultTypes::BrowseResult, results.first
    assert_equal "Solo Leveling", results.first.title
  end

  def test_browse_popular
    results = @adapter.browse(sort: "popular", page: 1, limit: 20)

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
  end

  def test_browse_returns_empty_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaKakalot::Adapter.new(config: { "base_url" => @base_url }, http: http)

    assert_equal [], adapter.browse(sort: "latest")
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="panel_story_list">
          <div class="story_item">
            <a href="/manga/one-piece">
              <img src="https://cdn.mangakakalot.gg/cover/one-piece.jpg" />
            </a>
            <h3><a href="/manga/one-piece">One Piece</a></h3>
          </div>
          <div class="story_item">
            <a href="/manga/one-piece-party">
              <img src="https://cdn.mangakakalot.gg/cover/one-piece-party.jpg" />
            </a>
            <h3><a href="/manga/one-piece-party">One Piece Party</a></h3>
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
      <body>
        <div class="manga-info-top">
          <div class="manga-info-pic">
            <img src="https://cdn.mangakakalot.gg/cover/one-piece.jpg" />
          </div>
          <h1>One Piece</h1>
          <ul>
            <li>Author(s) : <a href="/author/oda-eiichiro">Oda Eiichiro</a></li>
            <li>Status : Ongoing</li>
            <li>Genres : <a href="/genre/action">Action</a> <a href="/genre/adventure">Adventure</a></li>
          </ul>
        </div>
        <div class="story-alternative">ワンピース; OP</div>
        <div id="noidungm">A pirate adventure story.</div>
      </body>
      </html>
    HTML
  end

  def chapters_fixture
    {
      "data" => {
        "chapters" => [
          {
            "chapter_name" => "Chapter 1094: Five Elders",
            "chapter_slug" => "chapter-1094",
            "chapter_num" => 1094.0,
            "updated_at" => "2024-01-15T12:00:00.000000Z"
          },
          {
            "chapter_name" => "Chapter 1093: Luffy vs Kizaru",
            "chapter_slug" => "chapter-1093",
            "chapter_num" => 1093.0,
            "updated_at" => "2024-01-08T12:00:00.000000Z"
          }
        ],
        "pagination" => {
          "has_more" => false
        }
      }
    }.to_json
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <script>
          var cdns = ["https://cdn1.mangakakalot.gg", "https://cdn2.mangakakalot.gg"];
          var backupImage = ["https://backup.mangakakalot.gg"];
          var chapterImages = ["/path/to/page1.jpg", "/path/to/page2.jpg", "/path/to/page3.png"];
        </script>
        <div class="container-chapter-reader"></div>
      </body>
      </html>
    HTML
  end

  def pages_fallback_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="container-chapter-reader">
          <img src="https://cdn.mangakakalot.gg/fallback/page1.jpg" />
          <img src="https://cdn.mangakakalot.gg/fallback/page2.jpg" />
        </div>
      </body>
      </html>
    HTML
  end

  def browse_latest_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="truyen-list">
          <div class="list-truyen-item-wrap">
            <a href="/manga/solo-leveling">
              <img src="https://cdn.mangakakalot.gg/cover/solo-leveling.jpg" />
            </a>
            <h3><a href="/manga/solo-leveling">Solo Leveling</a></h3>
          </div>
          <div class="list-truyen-item-wrap">
            <a href="/manga/jujutsu-kaisen">
              <img src="https://cdn.mangakakalot.gg/cover/jjk.jpg" />
            </a>
            <h3><a href="/manga/jujutsu-kaisen">Jujutsu Kaisen</a></h3>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def browse_popular_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="truyen-list">
          <div class="list-truyen-item-wrap">
            <a href="/manga/one-piece">
              <img src="https://cdn.mangakakalot.gg/cover/one-piece.jpg" />
            </a>
            <h3><a href="/manga/one-piece">One Piece</a></h3>
          </div>
          <div class="list-truyen-item-wrap">
            <a href="/manga/naruto">
              <img src="https://cdn.mangakakalot.gg/cover/naruto.jpg" />
            </a>
            <h3><a href="/manga/naruto">Naruto</a></h3>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end
