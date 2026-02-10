require "test_helper"
require "json"
require "uri"

class MangaNatoAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://www.natomanga.com"
    @slug = "martial-peak"
    @chapter_slug = "chapter-3862"

    @fixtures = {
      "GET #{@base_url}/search/story/martial_peak" => search_fixture,
      "GET #{@base_url}/manga/#{@slug}" => series_fixture,
      "GET #{@base_url}/api/manga/#{@slug}/chapters" => chapters_fixture,
      "GET #{@base_url}/manga/#{@slug}/#{@chapter_slug}" => pages_fixture,
      "GET #{@base_url}/manga-list/latest-manga" => browse_latest_fixture,
      "GET #{@base_url}/manga-list/hot-manga" => browse_popular_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::MangaNato::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # ===== Search Tests =====

  def test_search_returns_results
    results = @adapter.search("martial peak")

    assert_equal 2, results.size
    assert_equal "Martial Peak", results.first.title
    assert_equal "martial-peak", results.first.id
    assert_equal "#{@base_url}/manga/martial-peak", results.first.url
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("martial peak")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("martial peak")

    assert_equal "https://img-r1.2xstorage.com/thumb/martial-peak.webp", results.first.cover_url
  end

  def test_search_normalizes_query
    # Spaces become underscores in the search URL
    results = @adapter.search("martial peak")

    assert_equal 2, results.size
  end

  def test_search_normalizes_special_characters
    # The adapter normalizes special characters to underscores
    # "martial-peak!" becomes "martial_peak" which matches the fixture
    results = @adapter.search("martial-peak!")

    assert_equal 2, results.size
    assert_equal "Martial Peak", results.first.title
  end

  def test_search_returns_empty_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaNato::Adapter.new(config: { "base_url" => @base_url }, http: http)

    results = adapter.search("nonexistent")

    assert_empty results
  end

  def test_search_extracts_author
    results = @adapter.search("martial peak")

    assert_equal "Pikapi", results.first.author
  end

  def test_search_handles_missing_author
    results = @adapter.search("martial peak")
    no_author = results.find { |r| r.title == "Martial Peak Colored" }

    assert_nil no_author&.author || nil
  end

  # ===== Series Tests =====

  def test_series_parses_details
    series = @adapter.series(@slug)

    assert_equal "Martial Peak", series.title
    assert_equal "martial-peak", series.id
    assert_equal "Momo", series.author
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Martial Arts"
  end

  def test_series_returns_series_struct
    series = @adapter.series(@slug)

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_from_full_url
    series = @adapter.series("#{@base_url}/manga/#{@slug}")

    assert_equal "Martial Peak", series.title
  end

  def test_series_cover_url
    series = @adapter.series(@slug)

    assert_equal "https://img-r1.2xstorage.com/thumb/martial-peak.webp", series.cover_url
  end

  def test_series_alt_titles
    series = @adapter.series(@slug)

    assert_includes series.alt_titles, "Wuliandianfeng"
    assert_includes series.alt_titles, "武炼巅峰"
  end

  def test_series_detects_manga_type
    series = @adapter.series(@slug)

    # The genres include "Manhua" so it should detect as manhua
    assert_equal "manhua", series.series_type
  end

  def test_series_extracts_description
    series = @adapter.series(@slug)

    assert_includes series.description, "peak of martial arts"
  end

  def test_series_extracts_artist
    series = @adapter.series(@slug)

    assert_equal "Pikapi", series.artist
  end

  def test_series_returns_nil_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaNato::Adapter.new(config: { "base_url" => @base_url }, http: http)

    assert_nil adapter.series("nonexistent")
  end

  def test_series_from_path_with_slashes
    # When given a path like "manga/martial-peak", normalize properly
    series = @adapter.series("manga/martial-peak")

    assert_equal "Martial Peak", series.title
  end

  # ===== Chapters Tests =====

  def test_chapters_returns_list
    chapters = @adapter.chapters(@slug)

    assert_equal 3, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters(@slug)

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_parses_number
    chapters = @adapter.chapters(@slug)

    numbers = chapters.map(&:number)

    assert_includes numbers, "3860"
    assert_includes numbers, "3861"
    assert_includes numbers, "3862"
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters(@slug)

    numbers = chapters.map { |ch| ch.number.to_f }

    assert_equal numbers.sort, numbers
  end

  def test_chapters_builds_url
    chapters = @adapter.chapters(@slug)
    ch = chapters.find { |c| c.number == "3862" }

    assert_equal "#{@base_url}/manga/martial-peak/chapter-3862", ch.url
  end

  def test_chapters_parses_title
    chapters = @adapter.chapters(@slug)
    ch = chapters.find { |c| c.number == "3862" }

    assert_equal "The Final Battle", ch.title
  end

  def test_chapters_parses_published_at
    chapters = @adapter.chapters(@slug)
    ch = chapters.find { |c| c.number == "3862" }

    assert_kind_of Time, ch.published_at
  end

  def test_chapters_group_is_manga_nato
    chapters = @adapter.chapters(@slug)

    chapters.each do |chapter|
      assert_equal "MangaNato", chapter.group
    end
  end

  def test_chapters_handles_decimal_numbers
    chapters = @adapter.chapters(@slug)
    ch = chapters.find { |c| c.number == "3860" }

    # 3860.0 should be formatted as "3860" (no decimal)
    assert_equal "3860", ch.number
  end

  def test_chapters_returns_empty_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaNato::Adapter.new(config: { "base_url" => @base_url }, http: http)

    assert_empty adapter.chapters("nonexistent")
  end

  def test_chapters_from_full_url
    chapters = @adapter.chapters("#{@base_url}/manga/#{@slug}")

    assert_equal 3, chapters.size
  end

  # ===== Pages Tests =====

  def test_pages_extracts_from_js_variables
    pages = @adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_equal 3, pages.size
    assert_equal 1, pages.first.index
    assert_equal "https://img-r1.2xstorage.com/martial-peak/3862/0.webp", pages.first.url
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_guesses_mime_type_webp
    pages = @adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_equal "image/webp", pages.first.mime_type
  end

  def test_pages_sequential_indexes
    pages = @adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    pages.each_with_index do |page, idx|
      assert_equal idx + 1, page.index
    end
  end

  def test_pages_fallback_to_img_tags
    fallback_fixtures = {
      "GET #{@base_url}/manga/#{@slug}/#{@chapter_slug}" => pages_fallback_fixture
    }
    http = FakeHttpClient.new(mapping: fallback_fixtures, base_url: @base_url)
    adapter = Scrapers::MangaNato::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_equal 2, pages.size
    assert_equal "https://img-r1.2xstorage.com/fallback/page1.jpg", pages.first.url
  end

  def test_pages_fallback_mime_type
    fallback_fixtures = {
      "GET #{@base_url}/manga/#{@slug}/#{@chapter_slug}" => pages_fallback_fixture
    }
    http = FakeHttpClient.new(mapping: fallback_fixtures, base_url: @base_url)
    adapter = Scrapers::MangaNato::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/manga/#{@slug}/#{@chapter_slug}")

    assert_equal "image/jpeg", pages.first.mime_type
  end

  def test_pages_returns_empty_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaNato::Adapter.new(config: { "base_url" => @base_url }, http: http)

    assert_empty adapter.pages("#{@base_url}/manga/foo/chapter-1")
  end

  # ===== Browse Tests =====

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_sort_options
    assert_equal %w[latest popular], @adapter.browse_sort_options
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

  def test_browse_includes_cover_url
    results = @adapter.browse(sort: "latest", page: 1, limit: 20)

    assert_not_nil results.first.cover_url
    assert_match %r{https://}, results.first.cover_url
  end

  def test_browse_builds_full_urls
    results = @adapter.browse(sort: "latest", page: 1, limit: 20)

    results.each do |result|
      assert result.url.start_with?(@base_url), "Expected URL to start with #{@base_url}, got: #{result.url}"
    end
  end

  def test_browse_returns_empty_on_error
    http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaNato::Adapter.new(config: { "base_url" => @base_url }, http: http)

    assert_empty adapter.browse(sort: "latest")
  end

  def test_browse_default_sort_is_latest
    results = @adapter.browse

    assert_equal 2, results.size
    assert_equal "Solo Leveling", results.first.title
  end

  # ===== Config Tests =====

  def test_uses_config_base_url
    custom_url = "https://custom.natomanga.com"
    adapter = Scrapers::MangaNato::Adapter.new(
      config: { "base_url" => custom_url },
      http: FakeHttpClient.new(mapping: {}, base_url: custom_url)
    )

    # Should use custom URL, which won't match any fixture
    results = adapter.search("test")

    assert_empty results
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="panel_story_list">
          <div class="story_item">
            <a href="/manga/martial-peak">
              <img src="https://img-r1.2xstorage.com/thumb/martial-peak.webp" />
            </a>
            <h3><a href="/manga/martial-peak">Martial Peak</a></h3>
            <span class="story_item_author">Author(s) : Pikapi</span>
          </div>
          <div class="story_item">
            <a href="/manga/martial-peak-colored">
              <img src="https://img-r1.2xstorage.com/thumb/martial-peak-colored.webp" />
            </a>
            <h3><a href="/manga/martial-peak-colored">Martial Peak Colored</a></h3>
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
            <img src="https://img-r1.2xstorage.com/thumb/martial-peak.webp" />
          </div>
          <h1>Martial Peak</h1>
          <ul>
            <li>Author(s) : <a href="/author/momo">Momo</a></li>
            <li>Artist(s) : <a href="/artist/pikapi">Pikapi</a></li>
            <li>Status : Ongoing</li>
            <li>Genres : <a href="/genre/action">Action</a> <a href="/genre/martial-arts">Martial Arts</a> <a href="/genre/manhua">Manhua</a></li>
          </ul>
        </div>
        <div class="story-alternative">Wuliandianfeng; 武炼巅峰</div>
        <div id="noidungm">The journey to the peak of martial arts is a lonely one.</div>
      </body>
      </html>
    HTML
  end

  def chapters_fixture
    {
      "data" => {
        "chapters" => [
          {
            "chapter_name" => "Chapter 3862: The Final Battle",
            "chapter_slug" => "chapter-3862",
            "chapter_num" => 3862.0,
            "updated_at" => "2024-12-20T08:00:00.000000Z"
          },
          {
            "chapter_name" => "Chapter 3861: Dawn of War",
            "chapter_slug" => "chapter-3861",
            "chapter_num" => 3861.0,
            "updated_at" => "2024-12-18T08:00:00.000000Z"
          },
          {
            "chapter_name" => "Chapter 3860",
            "chapter_slug" => "chapter-3860",
            "chapter_num" => 3860.0,
            "updated_at" => "2024-12-16T08:00:00.000000Z"
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
          var cdns = ["https://img-r1.2xstorage.com/", "https://imgs-2.2xstorage.com/"];
          var backupImage = ["https://backup.2xstorage.com/"];
          var chapterImages = ["martial-peak/3862/0.webp", "martial-peak/3862/1.webp", "martial-peak/3862/2.webp"];
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
          <img src="https://img-r1.2xstorage.com/fallback/page1.jpg" />
          <img src="https://img-r1.2xstorage.com/fallback/page2.jpg" />
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
              <img src="https://img-r1.2xstorage.com/thumb/solo-leveling.webp" />
            </a>
            <h3><a href="/manga/solo-leveling">Solo Leveling</a></h3>
          </div>
          <div class="list-truyen-item-wrap">
            <a href="/manga/tower-of-god">
              <img src="https://img-r1.2xstorage.com/thumb/tower-of-god.webp" />
            </a>
            <h3><a href="/manga/tower-of-god">Tower of God</a></h3>
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
              <img src="https://img-r1.2xstorage.com/thumb/one-piece.webp" />
            </a>
            <h3><a href="/manga/one-piece">One Piece</a></h3>
          </div>
          <div class="list-truyen-item-wrap">
            <a href="/manga/naruto">
              <img src="https://img-r1.2xstorage.com/thumb/naruto.webp" />
            </a>
            <h3><a href="/manga/naruto">Naruto</a></h3>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end
