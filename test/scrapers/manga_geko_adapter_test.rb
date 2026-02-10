require "test_helper"
require "json"
require "uri"

class MangaGekoAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = normalize_uri(build_uri(path_or_url, params))
      key = "GET #{uri}"
      body = @mapping[key]
      unless body
        fallback = uri.dup
        fallback.query = nil
        body = @mapping["GET #{fallback}"]
      end
      unless body
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

    def post(path_or_url, body: {}, headers: {}, params: {})
      uri = build_uri(path_or_url, params)
      key = "POST #{uri}"
      response_body = @mapping[key] || ""
      Response.new(status: response_body.empty? ? 404 : 200, body: response_body, headers: {}, url: uri.to_s)
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
    @base_url = "https://www.mgeko.cc"
    @series_slug = "eternally-regressing-knight"
    @chapter_slug = "eternally-regressing-knight-chapter-1-eng-li"
    @fixtures = {
      "GET #{@base_url}/ajax/manga/search/suggest?keyword=knight" => search_fixture,
      "GET #{@base_url}/manga/item/#{@series_slug}/" => series_fixture,
      "GET #{@base_url}/get/chapters/?manga_id=6070" => chapters_fixture,
      "GET #{@base_url}/chapter/en/#{@chapter_slug}/" => pages_fixture,
      "GET #{@base_url}/browse-comics/?filter=Updated&results=1" => browse_fixture,
      "GET #{@base_url}/browse-comics/?filter=Views&results=1" => browse_popular_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("knight")

    assert_equal 2, results.size
    assert_equal "Eternally Regressing Knight", results.first.title
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("knight")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("knight")

    assert_not_nil results.first.cover_url
    assert_match %r{https://}, results.first.cover_url
  end

  def test_search_builds_full_urls
    results = @adapter.search("knight")

    results.each do |result|
      assert result.url.start_with?(@base_url)
    end
  end

  def test_search_extracts_slug_as_id
    results = @adapter.search("knight")

    assert_equal "eternally-regressing-knight", results.first.id
  end

  def test_search_skips_nav_bottom_links
    results = @adapter.search("knight")

    # The "View all results" link with nav-bottom class should be excluded
    results.each do |result|
      refute_match(/View all results/i, result.title.to_s)
    end
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("knight")

    assert_empty results
  end

  def test_search_handles_invalid_json_gracefully
    bad_json_fixtures = {
      "GET #{@base_url}/ajax/manga/search/suggest?keyword=test" => "not valid json {{{}"
    }
    http = FakeHttpClient.new(mapping: bad_json_fixtures, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: http)

    results = adapter.search("test")

    assert_empty results
  end

  def test_search_handles_false_status_gracefully
    false_status_fixtures = {
      "GET #{@base_url}/ajax/manga/search/suggest?keyword=test" => { "status" => false }.to_json
    }
    http = FakeHttpClient.new(mapping: false_status_fixtures, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: http)

    results = adapter.search("test")

    assert_empty results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_equal "Eternally Regressing Knight", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Fantasy"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_not_nil series.cover_url
    assert_match %r{https://}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_not_nil series.description
    assert_includes series.description, "genius"
  end

  def test_series_detects_manhwa_type
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_equal "manhwa", series.series_type
  end

  def test_series_extracts_alt_titles
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_includes series.alt_titles, "The Eternal Regressor Knight"
  end

  def test_series_extracts_multiple_alt_titles
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_equal 2, series.alt_titles.size
    assert_includes series.alt_titles, "Yeongwonhi Hoegwihaneun Gisa"
  end

  def test_series_extracts_slug_as_id
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_equal @series_slug, series.id
  end

  def test_series_extracts_url
    url = "#{@base_url}/manga/item/#{@series_slug}/"
    series = @adapter.series(url)

    assert_equal url, series.url
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "Eternally Regressing Knight", series.title
  end

  def test_series_ignores_updating_alt_title
    fixtures = {
      "GET #{@base_url}/manga/item/test-updating/" => series_fixture_updating_alt
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: http)

    series = adapter.series("#{@base_url}/manga/item/test-updating/")

    assert_empty series.alt_titles
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/manga/item/nonexistent/")

    assert_nil result
  end

  # --- Chapters Tests ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    assert_equal 4, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_extracts_numbers
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    numbers = chapters.map(&:number).map(&:to_f)

    assert_includes numbers, 1.0
    assert_includes numbers, 2.0
    assert_includes numbers, 3.0
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    numbers = chapters.map { |ch| ch.number.to_f }

    assert_equal numbers.sort, numbers
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    chapters.each do |chapter|
      assert chapter.url.start_with?(@base_url)
      assert_match %r{/chapter/en/}, chapter.url
    end
  end

  def test_chapters_extracts_group
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    chapters.each do |chapter|
      assert_equal "MangaGeko", chapter.group
    end
  end

  def test_chapters_strips_eng_li_suffix_from_number
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    ch = chapters.find { |c| c.number == "3" }

    assert_not_nil ch
    # chapter_number "3-eng-li" should extract just "3"
    assert_equal "3", ch.number
  end

  def test_chapters_uses_slug_as_id
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    ch = chapters.find { |c| c.number == "1" }

    assert_equal "eternally-regressing-knight-chapter-1-eng-li", ch.id
  end

  def test_chapters_handles_decimal_numbers
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    decimal = chapters.find { |ch| ch.number == "1.5" }

    assert_not_nil decimal, "Should handle decimal chapter numbers"
  end

  def test_chapters_sets_language_to_english
    chapters = @adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    chapters.each do |chapter|
      assert_equal "en", chapter.language
    end
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/manga/item/nonexistent/")

    assert_empty result
  end

  def test_chapters_handles_missing_manga_id
    no_id_fixtures = {
      "GET #{@base_url}/manga/item/no-id-series/" => series_fixture_no_manga_id
    }
    http = FakeHttpClient.new(mapping: no_id_fixtures, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: http)

    result = adapter.chapters("#{@base_url}/manga/item/no-id-series/")

    assert_empty result
  end

  def test_chapters_handles_empty_chapters_array
    empty_chapters_fixtures = {
      "GET #{@base_url}/manga/item/#{@series_slug}/" => series_fixture,
      "GET #{@base_url}/get/chapters/?manga_id=6070" => { "chapters" => [] }.to_json
    }
    http = FakeHttpClient.new(mapping: empty_chapters_fixtures, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: http)

    result = adapter.chapters("#{@base_url}/manga/item/#{@series_slug}/")

    assert_empty result
  end

  # --- Pages Tests ---

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/chapter/en/#{@chapter_slug}/")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/chapter/en/#{@chapter_slug}/")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/chapter/en/#{@chapter_slug}/")

    pages.each do |page|
      assert page.url.start_with?("https://")
      assert_match /\.(jpg|jpeg|png|webp)/i, page.url
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/chapter/en/#{@chapter_slug}/")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_detects_webp_mime_type
    pages = @adapter.pages("#{@base_url}/chapter/en/#{@chapter_slug}/")

    webp_page = pages.find { |p| p.url.end_with?(".webp") }

    assert_not_nil webp_page
    assert_equal "image/webp", webp_page.mime_type
  end

  def test_pages_sequential_indices
    pages = @adapter.pages("#{@base_url}/chapter/en/#{@chapter_slug}/")

    pages.each_with_index do |page, idx|
      assert_equal idx, page.index
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/chapter/en/nonexistent/")

    assert_empty result
  end

  def test_pages_falls_back_to_generic_data_src_images
    fallback_fixtures = {
      "GET #{@base_url}/chapter/en/fallback-chapter/" => pages_fallback_fixture
    }
    http = FakeHttpClient.new(mapping: fallback_fixtures, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/chapter/en/fallback-chapter/")

    assert_equal 2, pages.size
    assert_match %r{https://}, pages.first.url
  end

  def test_pages_filters_non_page_urls
    filter_fixtures = {
      "GET #{@base_url}/chapter/en/filter-chapter/" => pages_with_non_page_images_fixture
    }
    http = FakeHttpClient.new(mapping: filter_fixtures, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/chapter/en/filter-chapter/")

    # Should only include the legitimate page images, not logos/avatars/icons
    assert_equal 2, pages.size
    pages.each do |page|
      refute_match(/logo|avatar|icon|favicon/i, page.url)
    end
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_sort_options
    assert_equal %w[latest popular], @adapter.browse_sort_options
  end

  def test_browse_latest_returns_results
    results = @adapter.browse(sort: "latest", page: 1)

    assert_operator results.size, :>, 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_result_has_title
    results = @adapter.browse(sort: "latest", page: 1)

    results.each do |result|
      assert_predicate result.title, :present?
    end
  end

  def test_browse_result_has_url
    results = @adapter.browse(sort: "latest", page: 1)

    results.each do |result|
      assert result.url.start_with?(@base_url)
    end
  end

  def test_browse_popular_returns_results
    results = @adapter.browse(sort: "popular", page: 1)

    assert_operator results.size, :>, 0
    assert_kind_of ResultTypes::BrowseResult, results.first
    assert_equal "One Piece", results.first.title
  end

  def test_browse_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.browse(sort: "latest", page: 1)

    assert_empty results
  end

  def test_browse_result_extracts_slug_as_id
    results = @adapter.browse(sort: "latest", page: 1)

    assert_equal "eternally-regressing-knight", results.first.id
  end

  def test_browse_result_sets_english_language
    results = @adapter.browse(sort: "latest", page: 1)

    results.each do |result|
      assert_equal "en", result.language
    end
  end

  # --- URL Normalization Tests ---

  def test_normalize_series_url_from_full_url
    series = @adapter.series("#{@base_url}/manga/item/#{@series_slug}/")

    assert_not_nil series
    assert_equal "Eternally Regressing Knight", series.title
  end

  def test_normalize_series_url_from_slug
    series = @adapter.series(@series_slug)

    assert_not_nil series
    assert_equal "Eternally Regressing Knight", series.title
  end

  def test_normalize_series_url_from_relative_path
    series = @adapter.series("/manga/item/#{@series_slug}/")

    assert_not_nil series
    assert_equal "Eternally Regressing Knight", series.title
  end

  # --- Config Tests ---

  def test_uses_config_base_url
    custom_url = "https://custom.mgeko.cc"
    custom_fixtures = {
      "GET #{custom_url}/ajax/manga/search/suggest?keyword=test" => search_fixture
    }
    http = FakeHttpClient.new(mapping: custom_fixtures, base_url: custom_url)
    adapter = Scrapers::MangaGeko::Adapter.new(config: { "base_url" => custom_url }, http: http)

    results = adapter.search("test")

    assert_equal 2, results.size
  end

  # --- Private Helper Tests ---

  def test_detect_series_type_from_type_text
    assert_equal "manhwa", @adapter.send(:detect_series_type, [], "Manhwa")
    assert_equal "manhua", @adapter.send(:detect_series_type, [], "Manhua")
    assert_equal "manga", @adapter.send(:detect_series_type, [], "Manga")
  end

  def test_detect_series_type_from_tags
    assert_equal "manhwa", @adapter.send(:detect_series_type, [ "Action", "Manhwa" ], nil)
    assert_equal "manhua", @adapter.send(:detect_series_type, [ "Action", "Chinese" ], nil)
    assert_equal "manga", @adapter.send(:detect_series_type, [ "Action", "Fantasy" ], nil)
  end

  def test_detect_series_type_defaults_to_manga
    assert_equal "manga", @adapter.send(:detect_series_type, [], nil)
  end

  def test_looks_like_page_url_filters_logos_and_icons
    refute @adapter.send(:looks_like_page_url?, "https://cdn.mgeko.cc/images/logo.png")
    refute @adapter.send(:looks_like_page_url?, "https://cdn.mgeko.cc/images/avatar.jpg")
    refute @adapter.send(:looks_like_page_url?, "https://cdn.mgeko.cc/images/icon.png")
    refute @adapter.send(:looks_like_page_url?, "https://cdn.mgeko.cc/favicon.ico")
    refute @adapter.send(:looks_like_page_url?, nil)
  end

  def test_looks_like_page_url_accepts_valid_urls
    assert @adapter.send(:looks_like_page_url?, "https://cdn.mgeko.cc/chapters/page-001.jpg")
    assert @adapter.send(:looks_like_page_url?, "https://imgsrv.mgeko.cc/chapters/page-001.webp")
    assert @adapter.send(:looks_like_page_url?, "https://cdn.example.com/manga/page.png")
  end

  def test_guess_mime_type_returns_correct_types
    assert_equal "image/jpeg", @adapter.send(:guess_mime_type, "page.jpg")
    assert_equal "image/png", @adapter.send(:guess_mime_type, "page.png")
    assert_equal "image/webp", @adapter.send(:guess_mime_type, "page.webp")
    assert_equal "image/gif", @adapter.send(:guess_mime_type, "page.gif")
    assert_equal "image/jpeg", @adapter.send(:guess_mime_type, "page.unknown")
  end

  def test_extract_slug_from_manga_url
    assert_equal "solo-leveling", @adapter.send(:extract_slug, "/manga/item/solo-leveling/")
    assert_equal "solo-leveling", @adapter.send(:extract_slug, "#{@base_url}/manga/item/solo-leveling/")
  end

  private

  def search_fixture
    {
      "status" => true,
      "html" => <<~HTML
        <a href="/manga/item/eternally-regressing-knight/" class="nav-item">
          <div class="manga-poster">
            <img src="https://cdn.mangageko.com/avatar/288x412/media/manga_covers/sa.jpg" class="manga-poster-img" alt="Eternally Regressing Knight">
          </div>
          <div class="srp-detail">
            <h3 class="manga-name">Eternally Regressing Knight</h3>
            <div class="film-infor">
              <span>Chap 96 [EN]</span>
            </div>
          </div>
          <div class="clearfix"></div>
        </a>
        <a href="/manga/item/return-of-the-knight-errant/" class="nav-item">
          <div class="manga-poster">
            <img src="https://cdn.mangageko.com/avatar/288x412/media/manga_covers/knight2.jpg" class="manga-poster-img" alt="Return of the Knight Errant">
          </div>
          <div class="srp-detail">
            <h3 class="manga-name">Return of the Knight Errant</h3>
            <div class="film-infor">
              <span>Chap 45 [EN]</span>
            </div>
          </div>
          <div class="clearfix"></div>
        </a>
        <a href="/browse-comics/?search=knight" class="nav-item nav-bottom">
          View all results<i class="fa fa-angle-right ml-2"></i>
        </a>
      HTML
    }.to_json
  end

  def series_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Eternally Regressing Knight - MangaGeko</title></head>
      <body>
        <div class="anisc-detail">
          <h2 class="manga-name">Eternally Regressing Knight</h2>
          <div class="manga-name-or">The Eternal Regressor Knight; Yeongwonhi Hoegwihaneun Gisa</div>
          <div class="manga-poster">
            <img src="https://imgsrv4.com/avatar/288x412/media/manga_covers/sa.jpg" class="manga-poster-img" alt="Eternally Regressing Knight">
          </div>
          <div class="genres">
            <a href="/browse-comics/?genre_included=Action&filter=Random">Action</a>
            <a href="/browse-comics/?genre_included=Adventure&filter=Random">Adventure</a>
            <a href="/browse-comics/?genre_included=Fantasy&filter=Random">Fantasy</a>
          </div>
          <div class="description">
            <div class="description-more">
              <div class="description-modal" style="color: black;">
                "You're a genius." Those words he heard as a child were poison.
              </div>
            </div>
          </div>
          <div class="anisc-info-wrap">
            <div class="anisc-info">
              <div class="item item-title">
                <span class="item-head">Type:</span>
                <a class="name" href="/type/manga">Manhwa</a>
              </div>
              <div class="item item-title">
                <span class="item-head">Status:</span>
                <span class="name">Ongoing</span>
              </div>
            </div>
          </div>
          <a href="/author/inaba-mifumi-534">Inaba Mifumi</a>
        </div>
        <script>
          fetch("/api/v1/addbookmark/", {'method': 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({manga_id: 6070 }) })
        </script>
        <script>
          fetch("/get/chapters/?manga_id=6070", {'method': 'GET'})
        </script>
      </body>
      </html>
    HTML
  end

  def series_fixture_no_manga_id
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="anisc-detail">
          <h2 class="manga-name">No ID Series</h2>
          <div class="description-modal">A series without a manga_id in the page.</div>
        </div>
      </body>
      </html>
    HTML
  end

  def series_fixture_updating_alt
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="anisc-detail">
          <h2 class="manga-name">Test Series</h2>
          <div class="manga-name-or">updating</div>
          <div class="anisc-info">
            <div class="item">
              <span class="item-head">Status:</span>
              <a class="name">Ongoing</a>
            </div>
          </div>
          <div class="description-modal">A test series.</div>
        </div>
      </body>
      </html>
    HTML
  end

  def chapters_fixture
    {
      "chapters" => [
        { "chapter_number" => "3-eng-li", "chapter_slug" => "eternally-regressing-knight-chapter-3-eng-li", "id" => 300001, "read" => "false" },
        { "chapter_number" => "2-eng-li", "chapter_slug" => "eternally-regressing-knight-chapter-2-eng-li", "id" => 200001, "read" => "false" },
        { "chapter_number" => "1.5-eng-li", "chapter_slug" => "eternally-regressing-knight-chapter-1.5-eng-li", "id" => 150001, "read" => "false" },
        { "chapter_number" => "1-eng-li", "chapter_slug" => "eternally-regressing-knight-chapter-1-eng-li", "id" => 100001, "read" => "false" }
      ],
      "marker_object" => "None",
      "bookmark" => "not-authenticated",
      "last_chapter" => "N"
    }.to_json
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Chapter 1 - Eternally Regressing Knight</title></head>
      <body>
        <div id="chapter-images" style="width: 100%;">
          <img class="lazy" data-src="https://imgsrv4.com/mg1/fastcdn/cdn_mangaraw/eternally-regressing-knight/chapter-1/1.jpg">
          <img class="lazy" data-src="https://imgsrv4.com/mg1/fastcdn/cdn_mangaraw/eternally-regressing-knight/chapter-1/2.jpg">
          <img class="lazy" data-src="https://imgsrv4.com/mg1/fastcdn/cdn_mangaraw/eternally-regressing-knight/chapter-1/3.webp">
        </div>
      </body>
      </html>
    HTML
  end

  def pages_fallback_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="reading-content">
          <img data-src="https://imgsrv4.com/mg1/fastcdn/cdn_mangaraw/fallback/page-001.jpg" src="placeholder.gif" />
          <img data-src="https://imgsrv4.com/mg1/fastcdn/cdn_mangaraw/fallback/page-002.png" src="placeholder.gif" />
        </div>
      </body>
      </html>
    HTML
  end

  def pages_with_non_page_images_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div id="chapter-images">
          <img class="lazy" data-src="https://imgsrv4.com/mg1/fastcdn/cdn_mangaraw/test/page-001.jpg" />
          <img class="lazy" data-src="https://cdn.mgeko.cc/images/logo.png" />
          <img class="lazy" data-src="https://cdn.mgeko.cc/images/avatar.jpg" />
          <img class="lazy" data-src="https://cdn.mgeko.cc/favicon.ico" />
          <img class="lazy" data-src="https://imgsrv4.com/mg1/fastcdn/cdn_mangaraw/test/page-002.jpg" />
        </div>
      </body>
      </html>
    HTML
  end

  def browse_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Browse Comics - MangaGeko</title></head>
      <body>
        <div class="film_list-wrap">
          <div class="flw-item">
            <a href="/manga/item/eternally-regressing-knight/" title="Eternally Regressing Knight">
              <img src="https://imgsrv4.com/avatar/288x412/media/manga_covers/sa.jpg" alt="Eternally Regressing Knight" />
            </a>
            <h3 class="manga-name"><a href="/manga/item/eternally-regressing-knight/">Eternally Regressing Knight</a></h3>
          </div>
          <div class="flw-item">
            <a href="/manga/item/part-time-grim-reaper/" title="Part-Time Grim Reaper">
              <img src="https://imgsrv4.com/avatar/288x412/media/manga_covers/grim.jpg" alt="Part-Time Grim Reaper" />
            </a>
            <h3 class="manga-name"><a href="/manga/item/part-time-grim-reaper/">Part-Time Grim Reaper</a></h3>
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
      <head><title>Browse Comics - Popular - MangaGeko</title></head>
      <body>
        <div class="film_list-wrap">
          <div class="flw-item">
            <a href="/manga/item/one-piece/" title="One Piece">
              <img src="https://imgsrv4.com/avatar/288x412/media/manga_covers/op.jpg" alt="One Piece" />
            </a>
            <h3 class="manga-name"><a href="/manga/item/one-piece/">One Piece</a></h3>
          </div>
          <div class="flw-item">
            <a href="/manga/item/naruto/" title="Naruto">
              <img src="https://imgsrv4.com/avatar/288x412/media/manga_covers/naruto.jpg" alt="Naruto" />
            </a>
            <h3 class="manga-name"><a href="/manga/item/naruto/">Naruto</a></h3>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end
