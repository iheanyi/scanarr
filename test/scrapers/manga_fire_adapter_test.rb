require "test_helper"
require "uri"

class MangaFireAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://mangafire.to"
    @manga_slug = "solo-leveling.38y"
    @chapter_number = "200"
    @fixtures = {
      "GET #{@base_url}/filter" => search_fixture,
      "GET #{@base_url}/manga/#{@manga_slug}" => series_fixture,
      "GET #{@base_url}/ajax/manga/#{@manga_slug}/chapter/en" => ajax_chapters_fixture,
      "GET #{@base_url}/ajax/read/#{@manga_slug}/en/chapter-#{@chapter_number}" => ajax_pages_fixture,
      "GET #{@base_url}/read/#{@manga_slug}/en/chapter-#{@chapter_number}" => html_pages_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("solo leveling")

    assert_equal 2, results.size
    assert_equal "Solo Leveling", results.first.title
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("solo leveling")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("solo leveling")

    assert_not_nil results.first.cover_url
    assert_match %r{https://static\.mfcdn\.cc/}, results.first.cover_url
  end

  def test_search_builds_full_urls
    results = @adapter.search("solo leveling")

    results.each do |result|
      assert result.url.start_with?(@base_url), "Expected URL to start with #{@base_url}, got: #{result.url}"
    end
  end

  def test_search_extracts_manga_id
    results = @adapter.search("solo leveling")

    assert_equal "solo-leveling.38y", results.first.id
  end

  def test_search_handles_empty_query
    results = @adapter.search("")

    assert_empty results
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("solo leveling")

    assert_empty results
  end

  # --- Series Tests ---

  def test_series_parses_title
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_equal "Solo Leveling", series.title
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_equal "Chugong", series.author
  end

  def test_series_extracts_status
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_equal "completed", series.status
  end

  def test_series_extracts_genres
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_includes series.tags, "Action"
    assert_includes series.tags, "Fantasy"
    assert_includes series.tags, "Adventure"
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_not_nil series.cover_url
    assert_match %r{static\.mfcdn\.cc}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_not_nil series.description
    assert_includes series.description, "Sung Jinwoo"
  end

  def test_series_extracts_alt_titles
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_includes series.alt_titles, "Na Honjaman Level Up"
  end

  def test_series_detects_manhwa_type
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_equal "manhwa", series.series_type
  end

  def test_series_from_slug
    series = @adapter.series(@manga_slug)

    assert_equal "Solo Leveling", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/manga/nonexistent.xyz")

    assert_nil result
  end

  # --- Chapters Tests (AJAX) ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    assert_equal 3, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_extracts_numbers
    chapters = @adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    numbers = chapters.map(&:number).map(&:to_f)

    assert_includes numbers, 198.0
    assert_includes numbers, 199.0
    assert_includes numbers, 200.0
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    numbers = chapters.map { |ch| ch.number.to_f }

    assert_equal numbers.sort, numbers
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    chapters.each do |chapter|
      assert chapter.url.start_with?(@base_url), "Expected URL to start with #{@base_url}, got: #{chapter.url}"
    end
  end

  def test_chapters_extracts_group
    chapters = @adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    chapters.each do |chapter|
      assert_equal "MangaFire", chapter.group
    end
  end

  def test_chapters_extracts_title
    chapters = @adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    titled_chapter = chapters.find { |ch| ch.number.to_f == 200.0 }

    assert_not_nil titled_chapter
    assert_equal "The End", titled_chapter.title
  end

  def test_chapters_extracts_published_date
    chapters = @adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    dated_chapter = chapters.find { |ch| ch.published_at.present? }

    assert_not_nil dated_chapter
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/manga/nonexistent.xyz")

    assert_empty result
  end

  # --- Chapters Tests (HTML fallback) ---

  def test_chapters_falls_back_to_html
    # Setup with no AJAX endpoint mapped
    html_only_fixtures = {
      "GET #{@base_url}/manga/#{@manga_slug}" => series_with_chapters_fixture
    }
    http = FakeHttpClient.new(mapping: html_only_fixtures, base_url: @base_url)
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: http)

    chapters = adapter.chapters("#{@base_url}/manga/#{@manga_slug}")

    assert_equal 2, chapters.size
    assert_equal "100", chapters.first.number
  end

  # --- Pages Tests (AJAX) ---

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/read/#{@manga_slug}/en/chapter-#{@chapter_number}")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/read/#{@manga_slug}/en/chapter-#{@chapter_number}")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/read/#{@manga_slug}/en/chapter-#{@chapter_number}")

    pages.each do |page|
      assert page.url.start_with?("https://"), "Expected URL to start with https://, got: #{page.url}"
      assert_match /\.(jpg|jpeg|png|webp)/i, page.url, "Expected image extension in URL: #{page.url}"
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/read/#{@manga_slug}/en/chapter-#{@chapter_number}")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_has_sequential_indices
    pages = @adapter.pages("#{@base_url}/read/#{@manga_slug}/en/chapter-#{@chapter_number}")

    pages.each_with_index do |page, idx|
      assert_equal idx, page.index
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/read/#{@manga_slug}/en/chapter-999")

    assert_empty result
  end

  # --- Pages Tests (HTML fallback) ---

  def test_pages_falls_back_to_html
    # Setup with only HTML page mapped (no AJAX)
    html_only_fixtures = {
      "GET #{@base_url}/read/#{@manga_slug}/en/chapter-1" => html_pages_fixture
    }
    http = FakeHttpClient.new(mapping: html_only_fixtures, base_url: @base_url)
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/read/#{@manga_slug}/en/chapter-1")

    assert_operator pages.size, :>, 0
    assert_kind_of ResultTypes::Page, pages.first
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_returns_results
    results = @adapter.browse(sort: "latest", page: 1)

    assert_operator results.size, :>, 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_result_has_title
    results = @adapter.browse(sort: "latest", page: 1)

    results.each do |result|
      assert_predicate result.title, :present?, "Browse result should have a title"
    end
  end

  def test_browse_result_has_url
    results = @adapter.browse(sort: "latest", page: 1)

    results.each do |result|
      assert result.url.start_with?(@base_url), "Expected URL to start with #{@base_url}"
    end
  end

  def test_browse_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.browse(sort: "latest", page: 1)

    assert_empty results
  end

  def test_browse_sort_options
    assert_equal %w[latest popular alphabetical], @adapter.browse_sort_options
  end

  # --- URL Normalization Tests ---

  def test_normalize_series_url_from_full_url
    series = @adapter.series("#{@base_url}/manga/#{@manga_slug}")

    assert_not_nil series
    assert_equal "Solo Leveling", series.title
  end

  def test_normalize_series_url_from_slug
    series = @adapter.series(@manga_slug)

    assert_not_nil series
    assert_equal "Solo Leveling", series.title
  end

  def test_normalize_series_url_from_path
    series = @adapter.series("/manga/#{@manga_slug}")

    assert_not_nil series
    assert_equal "Solo Leveling", series.title
  end

  # --- Manga ID Extraction Tests ---

  def test_extract_manga_id_from_url
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    id = adapter.send(:extract_manga_id, "/manga/one-piecee.dkw")

    assert_equal "one-piecee.dkw", id

    id = adapter.send(:extract_manga_id, "#{@base_url}/manga/solo-leveling.38y")

    assert_equal "solo-leveling.38y", id
  end

  def test_extract_chapter_number_from_url
    adapter = MangaFire::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    num = adapter.send(:extract_chapter_number, "/read/solo-leveling.38y/en/chapter-200")

    assert_equal "200", num

    num = adapter.send(:extract_chapter_number, "chapter-42.5")

    assert_equal "42.5", num
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Filter - MangaFire</title></head>
      <body>
        <div class="original card-lg">
          <div class="unit">
            <div class="inner">
              <a href="/manga/solo-leveling.38y">
                <img src="https://static.mfcdn.cc/abc123/i/covers/solo-leveling.jpg" alt="Solo Leveling" />
              </a>
              <div class="info">
                <a href="/manga/solo-leveling.38y">Solo Leveling</a>
              </div>
            </div>
          </div>
          <div class="unit">
            <div class="inner">
              <a href="/manga/solo-leveling-ragnarok.v9m2">
                <img src="https://static.mfcdn.cc/def456/i/covers/solo-leveling-ragnarok.jpg" alt="Solo Leveling: Ragnarok" />
              </a>
              <div class="info">
                <a href="/manga/solo-leveling-ragnarok.v9m2">Solo Leveling: Ragnarok</a>
              </div>
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
      <head><title>Solo Leveling - MangaFire</title></head>
      <body>
        <div class="main-inner">
          <div class="poster">
            <img src="https://static.mfcdn.cc/abc123/i/covers/solo-leveling.jpg" alt="Solo Leveling" />
          </div>
          <h1>Solo Leveling</h1>
          <h6>Na Honjaman Level Up; 나 혼자만 레벨업</h6>
          <div class="info">
            <p>Completed</p>
          </div>
          <div class="meta">
            <span>Author: </span><span><a href="/author/chugong">Chugong</a></span>
            <span>Type: </span><span>Manhwa</span>
            <span>Genres: </span><span>
              <a href="/genre/action">Action</a>,
              <a href="/genre/adventure">Adventure</a>,
              <a href="/genre/fantasy">Fantasy</a>,
              <a href="/genre/shounen">Shounen</a>
            </span>
          </div>
          <div id="synopsis">
            <div class="modal-content">
              10 years ago, after "the Gate" that connected the real world with the monster world opened, some of the ordinary, extract people received the power to hunt monsters within the Gate. They are known as "Hunters". However, not all Hunters are powerful. My name is Sung Jinwoo, an E-rank Hunter. I'm someone who has to risk his life in the lowliest of dungeons.
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def ajax_chapters_fixture
    {
      "result" => <<~HTML
        <ul>
          <li data-number="200">
            <a href="/read/solo-leveling.38y/en/chapter-200">
              <span>Chap 200: The End</span>
              <span>Dec 29, 2023</span>
            </a>
          </li>
          <li data-number="199">
            <a href="/read/solo-leveling.38y/en/chapter-199">
              <span>Chap 199: The Final Battle</span>
              <span>Dec 22, 2023</span>
            </a>
          </li>
          <li data-number="198">
            <a href="/read/solo-leveling.38y/en/chapter-198">
              <span>Chap 198</span>
              <span>Dec 15, 2023</span>
            </a>
          </li>
        </ul>
      HTML
    }.to_json
  end

  def ajax_pages_fixture
    {
      "result" => {
        "images" => [
          [ "https://static.mfcdn.cc/img1/solo-leveling/ch200/page-001.jpg", 800, 0 ],
          [ "https://static.mfcdn.cc/img2/solo-leveling/ch200/page-002.png", 800, 0 ],
          [ "https://static.mfcdn.cc/img3/solo-leveling/ch200/page-003.webp", 800, 0 ]
        ]
      }
    }.to_json
  end

  def html_pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Leveling Chapter 200 - MangaFire</title></head>
      <body>
        <div class="reader">
          <img src="https://static.mfcdn.cc/img1/solo-leveling/ch200/page-001.jpg" alt="Page 1" />
          <img src="https://static.mfcdn.cc/img2/solo-leveling/ch200/page-002.png" alt="Page 2" />
          <img src="https://static.mfcdn.cc/img3/solo-leveling/ch200/page-003.webp" alt="Page 3" />
        </div>
      </body>
      </html>
    HTML
  end

  def series_with_chapters_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Leveling - MangaFire</title></head>
      <body>
        <div class="main-inner">
          <div class="poster">
            <img src="https://static.mfcdn.cc/abc123/i/covers/solo-leveling.jpg" alt="Solo Leveling" />
          </div>
          <h1>Solo Leveling</h1>
          <h6>Na Honjaman Level Up</h6>
          <div class="info">
            <p>Completed</p>
          </div>
          <div class="meta">
            <span>Author: </span><span><a href="/author/chugong">Chugong</a></span>
            <span>Type: </span><span>Manhwa</span>
            <span>Genres: </span><span>
              <a href="/genre/action">Action</a>,
              <a href="/genre/fantasy">Fantasy</a>
            </span>
          </div>
          <div id="synopsis">
            <div class="modal-content">
              Sung Jinwoo is the weakest hunter.
            </div>
          </div>
          <ul>
            <li>
              <a href="/read/solo-leveling.38y/en/chapter-101">
                Chapter 101: The Shadow Army Jan 15, 2022
              </a>
            </li>
            <li>
              <a href="/read/solo-leveling.38y/en/chapter-100">
                Chapter 100: Double Dungeon Dec 30, 2021
              </a>
            </li>
          </ul>
        </div>
      </body>
      </html>
    HTML
  end
end
