require "test_helper"
require "uri"

class MangaFreakAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = build_uri(path_or_url, params)
      key = "GET #{uri}"
      body = @mapping[key]
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
    @base_url = "https://ww2.mangafreak.me"
    @series_slug = "One_Piece"
    @fixtures = {
      "GET #{@base_url}/Find/one_piece" => search_fixture,
      "GET #{@base_url}/Manga/#{@series_slug}" => series_fixture,
      "GET #{@base_url}/Read1_One_Piece_1" => pages_fixture,
      "GET #{@base_url}/Latest_Releases/1" => browse_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: @http)
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
    assert_match %r{images\.mangafreak\.me}, results.first.cover_url
  end

  def test_search_builds_full_urls
    results = @adapter.search("one piece")

    results.each do |result|
      assert result.url.start_with?(@base_url)
    end
  end

  def test_search_extracts_slug_as_id
    results = @adapter.search("one piece")

    assert_equal "One_Piece", results.first.id
    assert_equal "One_Piece_Colored", results.last.id
  end

  def test_search_extracts_second_result_title
    results = @adapter.search("one piece")

    assert_equal "One Piece - Colored", results.last.title
  end

  def test_search_normalizes_spaces_to_underscores
    # Query "one piece" should hit URL /Find/one_piece
    results = @adapter.search("one piece")

    assert_equal 2, results.size
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("one piece")

    assert_empty results
  end

  def test_search_returns_empty_for_no_results
    fixtures = {
      "GET #{@base_url}/Find/zzzznothing" => no_results_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: http)

    results = adapter.search("zzzznothing")

    assert_empty results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_equal "One Piece", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Adventure"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_equal "Oda, Eiichiro", series.author
  end

  def test_series_extracts_artist
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_equal "Oda, Eiichiro", series.artist
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_not_nil series.cover_url
    assert_match %r{images\.mangafreak\.me}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_not_nil series.description
    assert_includes series.description, "Monkey D. Luffy"
  end

  def test_series_extracts_alt_titles
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_includes series.alt_titles, "One Piece"
  end

  def test_series_detects_manga_type_right_to_left
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    # Right to Left = manga
    assert_equal "manga", series.series_type
  end

  def test_series_extracts_all_genres
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_equal 4, series.tags.size
    assert_includes series.tags, "Comedy"
    assert_includes series.tags, "Shounen"
  end

  def test_series_extracts_id_from_slug
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_equal "One_Piece", series.id
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "One Piece", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/Manga/nonexistent")

    assert_nil result
  end

  def test_series_detects_completed_status
    fixtures = {
      "GET #{@base_url}/Manga/Solo_Leveling" => completed_series_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: http)

    series = adapter.series("#{@base_url}/Manga/Solo_Leveling")

    assert_equal "completed", series.status
  end

  def test_series_detects_manhwa_type_left_to_right
    fixtures = {
      "GET #{@base_url}/Manga/Solo_Leveling" => completed_series_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: http)

    series = adapter.series("#{@base_url}/Manga/Solo_Leveling")

    # Left to Right = manhwa
    assert_equal "manhwa", series.series_type
  end

  def test_series_url_stored_correctly
    series = @adapter.series("#{@base_url}/Manga/#{@series_slug}")

    assert_equal "#{@base_url}/Manga/One_Piece", series.url
  end

  # --- Chapters Tests ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    assert_equal 3, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_extracts_numbers
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    numbers = chapters.map(&:number).map(&:to_f)

    assert_includes numbers, 1.0
    assert_includes numbers, 2.0
    assert_includes numbers, 3.0
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    numbers = chapters.map { |ch| ch.number.to_f }

    assert_equal numbers.sort, numbers
  end

  def test_chapters_extracts_title
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    ch1 = chapters.find { |ch| ch.number == "1" }

    assert_equal "Romance Dawn", ch1.title
  end

  def test_chapters_without_title_has_nil_title
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    ch3 = chapters.find { |ch| ch.number == "3" }

    assert_nil ch3.title
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    chapters.each do |chapter|
      assert chapter.url.start_with?(@base_url)
    end
  end

  def test_chapters_url_format
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    ch1 = chapters.find { |ch| ch.number == "1" }

    assert_equal "#{@base_url}/Read1_One_Piece_1", ch1.url
  end

  def test_chapters_extracts_group
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    chapters.each do |chapter|
      assert_equal "MangaFreak", chapter.group
    end
  end

  def test_chapters_language_is_english
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    chapters.each do |chapter|
      assert_equal "en", chapter.language
    end
  end

  def test_chapters_extracts_published_date
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    dated_chapter = chapters.find { |ch| ch.published_at.present? }

    assert_not_nil dated_chapter
    assert_kind_of Date, dated_chapter.published_at
  end

  def test_chapters_parses_date_correctly
    chapters = @adapter.chapters("#{@base_url}/Manga/#{@series_slug}")

    ch1 = chapters.find { |ch| ch.number == "1" }

    assert_equal Date.new(2009, 7, 6), ch1.published_at
  end

  def test_chapters_handles_decimal_numbers
    fixtures = {
      "GET #{@base_url}/Manga/Decimal_Series" => decimal_chapters_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: http)

    chapters = adapter.chapters("#{@base_url}/Manga/Decimal_Series")

    numbers = chapters.map(&:number)

    assert_includes numbers, "12"
    assert_includes numbers, "12.5"
    assert_includes numbers, "13"
  end

  def test_chapters_decimal_sorted_correctly
    fixtures = {
      "GET #{@base_url}/Manga/Decimal_Series" => decimal_chapters_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: http)

    chapters = adapter.chapters("#{@base_url}/Manga/Decimal_Series")
    numbers = chapters.map { |ch| ch.number.to_f }

    assert_equal [ 12.0, 12.5, 13.0 ], numbers
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/Manga/nonexistent")

    assert_empty result
  end

  # --- Pages Tests ---

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/Read1_One_Piece_1")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/Read1_One_Piece_1")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/Read1_One_Piece_1")

    pages.each do |page|
      assert page.url.start_with?("https://"), "Expected URL to start with https://, got: #{page.url}"
      assert_match /\.(jpg|jpeg|png|webp)/i, page.url, "Expected image extension, got: #{page.url}"
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/Read1_One_Piece_1")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_detects_jpeg_mime_type
    pages = @adapter.pages("#{@base_url}/Read1_One_Piece_1")

    jpg_page = pages.find { |p| p.url.end_with?(".jpg") }

    assert_not_nil jpg_page
    assert_equal "image/jpeg", jpg_page.mime_type
  end

  def test_pages_has_sequential_indices
    pages = @adapter.pages("#{@base_url}/Read1_One_Piece_1")

    pages.each_with_index do |page, idx|
      assert_equal idx, page.index
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/Read1_One_Piece_999")

    assert_empty result
  end

  def test_pages_with_image_orientation_wrapper
    # Test with the actual MangaFreak reader structure (image_orientation divs)
    fixtures = {
      "GET #{@base_url}/Read1_Solo_Leveling_1" => pages_with_wrapper_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/Read1_Solo_Leveling_1")

    assert_equal 3, pages.size
    assert_match %r{solo_leveling}, pages.first.url
  end

  def test_pages_detects_webp_mime_type
    fixtures = {
      "GET #{@base_url}/Read1_Webp_Test_1" => pages_webp_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/Read1_Webp_Test_1")

    webp_page = pages.find { |p| p.url.end_with?(".webp") }

    assert_not_nil webp_page
    assert_equal "image/webp", webp_page.mime_type
  end

  def test_pages_detects_png_mime_type
    fixtures = {
      "GET #{@base_url}/Read1_Png_Test_1" => pages_png_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/Read1_Png_Test_1")

    assert_equal "image/png", pages.first.mime_type
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_sort_options
    assert_equal %w[latest], @adapter.browse_sort_options
  end

  def test_browse_returns_results
    results = @adapter.browse(sort: "latest", page: 1)

    assert_equal 2, results.size
  end

  def test_browse_returns_browse_result_structs
    results = @adapter.browse(sort: "latest", page: 1)

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

  def test_browse_extracts_cover
    results = @adapter.browse(sort: "latest", page: 1)

    assert_not_nil results.first.cover_url
    assert_match %r{images\.mangafreak\.me}, results.first.cover_url
  end

  def test_browse_extracts_slug_as_id
    results = @adapter.browse(sort: "latest", page: 1)

    assert_equal "One_Piece", results.first.id
  end

  def test_browse_detects_ongoing_status
    results = @adapter.browse(sort: "latest", page: 1)

    ongoing = results.find { |r| r.id == "One_Piece" }

    assert_equal "ongoing", ongoing.status
  end

  def test_browse_detects_completed_status
    results = @adapter.browse(sort: "latest", page: 1)

    completed = results.find { |r| r.id == "Dandadan" }

    assert_equal "completed", completed.status
  end

  def test_browse_sets_language_to_english
    results = @adapter.browse(sort: "latest", page: 1)

    results.each do |result|
      assert_equal "en", result.language
    end
  end

  def test_browse_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.browse(sort: "latest", page: 1)

    assert_empty results
  end

  # --- Config Base URL Tests ---

  def test_uses_config_base_url
    custom_url = "https://custom.mangafreak.me"
    fixtures = {
      "GET #{custom_url}/Find/test" => search_fixture
    }
    http = FakeHttpClient.new(mapping: fixtures, base_url: custom_url)
    adapter = Scrapers::MangaFreak::Adapter.new(config: { "base_url" => custom_url }, http: http)

    results = adapter.search("test")

    assert_operator results.size, :>, 0
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Search Query for one_piece - MangaFreak</title></head>
      <body>
        <div class="search_result_box">
          <div class="search_result">
            <div class="manga_result">
              <h3>Manga/Manhwa Result</h3>
              <div class="manga_search_item">
                <h6>1.</h6>
                <span>
                  <a href="/Manga/One_Piece"><img src="https://images.mangafreak.me/manga_images/one_piece.jpg"></a>
                </span>
                <span>
                  <h3><a href="/Manga/One_Piece">One Piece</a></h3>
                  <div>1173 Chapters Published. (Ongoing)</div>
                  <strong>Manga (Read Right to Left)</strong>
                  <div>
                    <a href="/Genre/Action">Action</a>, <a href="/Genre/Adventure">Adventure</a>
                  </div>
                </span>
              </div>
              <div class="manga_search_item">
                <h6>2.</h6>
                <span>
                  <a href="/Manga/One_Piece_Colored"><img src="https://images.mangafreak.me/manga_images/one_piece_colored.jpg"></a>
                </span>
                <span>
                  <h3><a href="/Manga/One_Piece_Colored">One Piece - Colored</a></h3>
                  <div>550 Chapters Published. (Ongoing)</div>
                  <strong>Manga (Read Right to Left)</strong>
                  <div>
                    <a href="/Genre/Action">Action</a>
                  </div>
                </span>
              </div>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def no_results_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Search Query for zzzznothing - MangaFreak</title></head>
      <body>
        <div class="search_result_box">
          <div class="search_result">
            <div class="manga_result">
              <h3>Manga/Manhwa Result</h3>
            </div>
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
      <head><title>One Piece Manga - MangaFreak</title></head>
      <body>
        <div class="series_info">
          <div class="manga_series_info_section">
            <div class="manga_series_info">
              <div class="manga_series_image">
                <img src="https://images.mangafreak.me/manga_images/one_piece.jpg">
              </div>
              <div class="manga_series_data">
                <h1>One Piece</h1>
                <div>Alternative Title: One Piece</div>
                <div>This is ON-GOING series</div>
                <div>Type: Right(&#8594;) to Left(&#8592;)</div>
                <div>Written By: Oda, Eiichiro</div>
                <div>Illustrated By: Oda, Eiichiro</div>
                <div>Year Published: 1997</div>
                <div class="series_sub_genre_list">
                  <a href="/Genre/Action">Action</a>
                  <a href="/Genre/Adventure">Adventure</a>
                  <a href="/Genre/Comedy">Comedy</a>
                  <a href="/Genre/Shounen">Shounen</a>
                </div>
              </div>
            </div>
          </div>
          <div class="manga_series_description_section">
            <div class="manga_series_description">
              <div>Synopsis</div>
              <p>Seeking to be the greatest pirate in the world, young Monkey D. Luffy, endowed with stretching powers from the legendary "Gomu Gomu" Devil's fruit, travels towards the Grand Line in search of One Piece.</p>
            </div>
          </div>
          <div class="manga_series_list_section">
            <div class="manga_series_list">
              <table>
                <thead>
                  <th>Title</th>
                  <th>Timeline</th>
                </thead>
                <tr>
                  <td><a href="/Read1_One_Piece_1">Chapter 1 - Romance Dawn</a></td>
                  <td>2009/07/06</td>
                </tr>
                <tr>
                  <td><a href="/Read1_One_Piece_2">Chapter 2 - They Call Him Strawhat Luffy</a></td>
                  <td>2009/07/06</td>
                </tr>
                <tr>
                  <td><a href="/Read1_One_Piece_3">Chapter 3</a></td>
                  <td>2009/07/06</td>
                </tr>
              </table>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def completed_series_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Leveling Manga - MangaFreak</title></head>
      <body>
        <div class="series_info">
          <div class="manga_series_info_section">
            <div class="manga_series_info">
              <div class="manga_series_image">
                <img src="https://images.mangafreak.me/manga_images/solo_leveling.jpg">
              </div>
              <div class="manga_series_data">
                <h1>Solo Leveling</h1>
                <div>Alternative Title: Na Honjaman Level Up</div>
                <div>This is COMPLETED series</div>
                <div>Type: Left(&#8592;) to Right(&#8594;)</div>
                <div>Written By: Jang Sung-lak</div>
                <div>Illustrated By: Gee So-lyung</div>
                <div>Year Published: 2018</div>
                <div class="series_sub_genre_list">
                  <a href="/Genre/Action">Action</a>
                  <a href="/Genre/Adventure">Adventure</a>
                  <a href="/Genre/Fantasy">Fantasy</a>
                  <a href="/Genre/Shounen">Shounen</a>
                </div>
              </div>
            </div>
          </div>
          <div class="manga_series_description_section">
            <div class="manga_series_description">
              <div>Synopsis</div>
              <p>10 years ago, after "the Gate" that connected the real world with the monster world opened, some of the ordinary, everyday people received the power to hunt monsters within the Gate.</p>
            </div>
          </div>
          <div class="manga_series_list_section">
            <div class="manga_series_list">
              <table>
                <thead>
                  <th>Title</th>
                  <th>Timeline</th>
                </thead>
                <tr>
                  <td><a href="/Read1_Solo_Leveling_1">Chapter 1</a></td>
                  <td>2018/11/15</td>
                </tr>
                <tr>
                  <td><a href="/Read1_Solo_Leveling_200">Chapter 200</a></td>
                  <td>2021/12/29</td>
                </tr>
              </table>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def decimal_chapters_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Decimal Series - MangaFreak</title></head>
      <body>
        <div class="series_info">
          <div class="manga_series_info_section">
            <div class="manga_series_info">
              <div class="manga_series_image">
                <img src="https://images.mangafreak.me/manga_images/decimal_series.jpg">
              </div>
              <div class="manga_series_data">
                <h1>Decimal Series</h1>
                <div>Alternative Title: </div>
                <div>This is ON-GOING series</div>
                <div>Type: Right(&#8594;) to Left(&#8592;)</div>
                <div>Written By: Author</div>
                <div>Illustrated By: Artist</div>
                <div class="series_sub_genre_list">
                  <a href="/Genre/Action">Action</a>
                </div>
              </div>
            </div>
          </div>
          <div class="manga_series_list_section">
            <div class="manga_series_list">
              <table>
                <thead>
                  <th>Title</th>
                  <th>Timeline</th>
                </thead>
                <tr>
                  <td><a href="/Read1_Decimal_Series_12">Chapter 12</a></td>
                  <td>2023/01/01</td>
                </tr>
                <tr>
                  <td><a href="/Read1_Decimal_Series_12.5">Chapter 12.5 - Extra</a></td>
                  <td>2023/01/08</td>
                </tr>
                <tr>
                  <td><a href="/Read1_Decimal_Series_13">Chapter 13</a></td>
                  <td>2023/01/15</td>
                </tr>
              </table>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece Chapter 1 - MangaFreak</title></head>
      <body>
        <div class="read_container">
          <img id="gohere" src="https://images.mangafreak.me/mangas/one_piece/one_piece_1/one_piece_1_1.jpg" alt="One Piece Chapter 1 Page 1" loading="lazy" width="1200" height="884">
          <img id="gohere" src="https://images.mangafreak.me/mangas/one_piece/one_piece_1/one_piece_1_2.jpg" alt="One Piece Chapter 1 Page 2" loading="lazy" width="546" height="885">
          <img id="gohere" src="https://images.mangafreak.me/mangas/one_piece/one_piece_1/one_piece_1_3.jpg" alt="One Piece Chapter 1 Page 3" loading="lazy" width="552" height="902">
        </div>
      </body>
      </html>
    HTML
  end

  def pages_with_wrapper_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Leveling Chapter 1 - MangaFreak</title></head>
      <body>
        <div class="read_manga">
          <div class="image_orientation" style="max-width: 600px;">
            <div class="mySlides fade" style="padding-bottom: 116%; display:block;">
              <img id="gohere" src="https://images.mangafreak.me/mangas/solo_leveling/solo_leveling_1/solo_leveling_1_1.jpg" alt="Solo Leveling Chapter 1 Page 1" loading="lazy" width="600" height="700">
            </div>
          </div>
          <div class="image_orientation" style="max-width: 720px;">
            <div class="mySlides fade" style="padding-bottom: 650%;">
              <img id="gohere" src="https://images.mangafreak.me/mangas/solo_leveling/solo_leveling_1/solo_leveling_1_2.jpg" alt="Solo Leveling Chapter 1 Page 2" loading="lazy" width="720" height="4685">
            </div>
          </div>
          <div class="image_orientation" style="max-width: 720px;">
            <div class="mySlides fade" style="padding-bottom: 642%;">
              <img id="gohere" src="https://images.mangafreak.me/mangas/solo_leveling/solo_leveling_1/solo_leveling_1_3.jpg" alt="Solo Leveling Chapter 1 Page 3" loading="lazy" width="720" height="4626">
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def pages_webp_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Webp Test Chapter 1 - MangaFreak</title></head>
      <body>
        <div class="read_container">
          <img id="gohere" src="https://images.mangafreak.me/mangas/test/test_1/test_1_1.webp" alt="Test Page 1" loading="lazy">
          <img id="gohere" src="https://images.mangafreak.me/mangas/test/test_1/test_1_2.webp" alt="Test Page 2" loading="lazy">
        </div>
      </body>
      </html>
    HTML
  end

  def pages_png_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Png Test Chapter 1 - MangaFreak</title></head>
      <body>
        <div class="read_container">
          <img id="gohere" src="https://images.mangafreak.me/mangas/test/test_1/test_1_1.png" alt="Test Page 1" loading="lazy">
        </div>
      </body>
      </html>
    HTML
  end

  def browse_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Latest Manga Releases - MangaFreak</title></head>
      <body>
        <div class="latest_releases">
          <div class="latest_releases_list">
            <div class="latest_releases_item">
              <div class="latest_releases_image ongoing_pic">
                <img src="https://images.mangafreak.me/mini_images/one_piece/55x85">
              </div>
              <div class="latest_releases_info">
                <a href="/Manga/One_Piece"><strong>One Piece</strong></a>
                <div>
                  <div><a href="/Read1_One_Piece_1173">One Piece 1173</a></div>
                </div>
              </div>
              <div class="latest_releases_time">Today</div>
            </div>
            <div class="latest_releases_item">
              <div class="latest_releases_image completed_pic">
                <img src="https://images.mangafreak.me/mini_images/dandadan/55x85">
              </div>
              <div class="latest_releases_info">
                <a href="/Manga/Dandadan"><strong>Dandadan</strong></a>
                <div>
                  <div><a href="/Read1_Dandadan_180">Dandadan 180</a></div>
                </div>
              </div>
              <div class="latest_releases_time">Yesterday</div>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end
