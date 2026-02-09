require "test_helper"

class Manhwa18AdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = URI(path_or_url.to_s)
      uri = URI.join(@base_url, path_or_url.to_s) if uri.host.nil?
      query = URI.encode_www_form(params) unless params.empty?
      full_uri = query ? "#{uri}?#{query}" : uri.to_s
      key = "GET #{full_uri}"
      body = @mapping[key] || @mapping["GET #{uri}"]
      status = body ? 200 : 404
      Response.new(status: status, body: body || "", headers: {}, url: full_uri)
    end
  end

  def setup
    @base_url = "https://manhwa18.net"
    @fixtures = {
      "GET #{@base_url}/tim-kiem?q=solo" => search_fixture,
      "GET #{@base_url}/manga/solo-max-level-newbie" => series_fixture,
      "GET #{@base_url}/manga/solo-max-level-newbie/chapter-1-319" => pages_fixture,
      "GET #{@base_url}/manga-list?page=1&sort=most-view" => browse_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # -- Search tests --

  def test_search_returns_results
    results = @adapter.search("solo")

    assert_equal 2, results.size
  end

  def test_search_extracts_title
    results = @adapter.search("solo")

    assert_equal "Solo Max-Level Newbie", results.first.title
  end

  def test_search_builds_url
    results = @adapter.search("solo")

    assert_equal "#{@base_url}/manga/solo-max-level-newbie", results.first.url
  end

  def test_search_extracts_cover_url
    results = @adapter.search("solo")

    assert_equal "#{@base_url}/storage/images/raw/abc123.jpg", results.first.cover_url
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("solo")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_no_results
    results = @adapter.search("nonexistent manga xyz")

    assert_empty results
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("solo")

    assert_empty results
  end

  def test_search_extracts_slug_as_id
    results = @adapter.search("solo")

    assert_equal "solo-max-level-newbie", results.first.id
  end

  # -- Series tests --

  def test_series_parses_title
    series = @adapter.series("#{@base_url}/manga/solo-max-level-newbie")

    assert_equal "Solo Max-Level Newbie", series.title
  end

  def test_series_parses_alt_titles
    series = @adapter.series("#{@base_url}/manga/solo-max-level-newbie")

    assert_includes series.alt_titles, "Solo Max-Level Newbie manhwa"
  end

  def test_series_parses_status
    series = @adapter.series("#{@base_url}/manga/solo-max-level-newbie")

    assert_equal "ongoing", series.status
  end

  def test_series_parses_description
    series = @adapter.series("#{@base_url}/manga/solo-max-level-newbie")

    assert_match(/gaming Nutuber/, series.description)
  end

  def test_series_parses_cover_url
    series = @adapter.series("#{@base_url}/manga/solo-max-level-newbie")

    assert_equal "#{@base_url}/storage/images/raw/cover123.jpg", series.cover_url
  end

  def test_series_parses_genres
    series = @adapter.series("#{@base_url}/manga/solo-max-level-newbie")

    assert_includes series.tags, "Manhwa"
    assert_includes series.tags, "Action"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/manga/solo-max-level-newbie")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_type_is_manhwa
    series = @adapter.series("#{@base_url}/manga/solo-max-level-newbie")

    assert_equal "manhwa", series.series_type
  end

  def test_series_returns_nil_for_not_found
    series = @adapter.series("#{@base_url}/manga/nonexistent-manga")

    assert_nil series
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/manga/nonexistent")

    assert_nil result
  end

  def test_series_from_slug
    series = @adapter.series("solo-max-level-newbie")

    assert_equal "Solo Max-Level Newbie", series.title
  end

  # -- Chapters tests --

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/manga/solo-max-level-newbie")

    assert_equal 3, chapters.size
  end

  def test_chapters_extracts_number
    chapters = @adapter.chapters("#{@base_url}/manga/solo-max-level-newbie")
    numbers = chapters.map(&:number)

    assert_includes numbers, "1"
    assert_includes numbers, "2"
    assert_includes numbers, "3"
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/manga/solo-max-level-newbie")

    assert_equal "1", chapters.first.number
    assert_equal "3", chapters.last.number
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/manga/solo-max-level-newbie")

    assert_equal "#{@base_url}/manga/solo-max-level-newbie/chapter-1-319", chapters.first.url
  end

  def test_chapters_sets_group
    chapters = @adapter.chapters("#{@base_url}/manga/solo-max-level-newbie")

    assert_equal "Manhwa18", chapters.first.group
  end

  def test_chapters_parses_date
    chapters = @adapter.chapters("#{@base_url}/manga/solo-max-level-newbie")
    ch = chapters.find { |c| c.number == "1" }

    assert_equal Date.new(2021, 5, 11), ch.published_at
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/manga/solo-max-level-newbie")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/manga/nonexistent")

    assert_empty result
  end

  def test_chapters_from_slug
    chapters = @adapter.chapters("solo-max-level-newbie")

    assert_equal 3, chapters.size
  end

  def test_chapters_extracts_title
    chapters = @adapter.chapters("#{@base_url}/manga/solo-max-level-newbie")

    # Chapter titles on manhwa18 are just "Chapter N" so title is just the name
    chapters.each do |chapter|
      assert_not_nil chapter.title
    end
  end

  # -- Pages tests --

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/manga/solo-max-level-newbie/chapter-1-319")

    assert_equal 3, pages.size
  end

  def test_pages_extracts_cdn_urls
    pages = @adapter.pages("#{@base_url}/manga/solo-max-level-newbie/chapter-1-319")

    assert_match(/cdn\.manhwa18\.com/, pages.first.url)
  end

  def test_pages_sets_index
    pages = @adapter.pages("#{@base_url}/manga/solo-max-level-newbie/chapter-1-319")

    assert_equal 0, pages.first.index
    assert_equal 1, pages[1].index
    assert_equal 2, pages[2].index
  end

  def test_pages_detects_mime_type
    pages = @adapter.pages("#{@base_url}/manga/solo-max-level-newbie/chapter-1-319")

    assert_equal "image/jpeg", pages.first.mime_type
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/manga/solo-max-level-newbie/chapter-1-319")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/manga/solo-max-level-newbie/chapter-999-999")

    assert_empty result
  end

  def test_pages_filters_out_non_page_urls
    fixture = {
      "GET #{@base_url}/manga/test/chapter-1-1" => pages_with_junk_fixture
    }
    http = FakeHttpClient.new(mapping: fixture, base_url: @base_url)
    adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/manga/test/chapter-1-1")

    # Should only include real page images, not logos/icons
    pages.each do |page|
      refute_match(/logo|icon|favicon/, page.url)
    end
    assert_equal 2, pages.size
  end

  def test_pages_detects_webp_mime_type
    fixture = {
      "GET #{@base_url}/manga/test/chapter-1-1" => pages_webp_fixture
    }
    http = FakeHttpClient.new(mapping: fixture, base_url: @base_url)
    adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/manga/test/chapter-1-1")

    assert_equal "image/webp", pages.first.mime_type
  end

  # -- Browse tests --

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_returns_results
    results = @adapter.browse(sort: "popular", page: 1)

    assert_equal 2, results.size
  end

  def test_browse_extracts_title
    results = @adapter.browse(sort: "popular", page: 1)

    assert_equal "Solo Max-Level Newbie", results.first.title
  end

  def test_browse_extracts_cover_url
    results = @adapter.browse(sort: "popular", page: 1)

    assert_equal "#{@base_url}/storage/images/raw/cover123.jpg", results.first.cover_url
  end

  def test_browse_returns_browse_result_structs
    results = @adapter.browse(sort: "popular", page: 1)

    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_extracts_chapter_count
    results = @adapter.browse(sort: "popular", page: 1)

    assert_equal 20, results.first.chapter_count
  end

  def test_browse_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.browse(sort: "latest", page: 1)

    assert_empty results
  end

  def test_browse_latest_uses_latest_sort
    fixture = {
      "GET #{@base_url}/manga-list?page=1&sort=latest" => browse_fixture
    }
    http = FakeHttpClient.new(mapping: fixture, base_url: @base_url)
    adapter = Scrapers::Manhwa18::Adapter.new(config: { "base_url" => @base_url }, http: http)

    results = adapter.browse(sort: "latest", page: 1)

    assert_equal 2, results.size
  end

  def test_browse_builds_full_urls
    results = @adapter.browse(sort: "popular", page: 1)

    results.each do |result|
      assert result.url.start_with?(@base_url)
    end
  end

  def test_browse_sort_options
    assert_equal %w[latest popular], @adapter.browse_sort_options
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="thumb-item-flow col-6 col-md-2">
          <div class="thumb-wrapper" data-id="842">
            <a href="https://manhwa18.net/manga/solo-max-level-newbie">
              <div class="a6-ratio">
                <div class="content img-in-ratio" data-bg="#{@base_url}/storage/images/raw/abc123.jpg"
                     style="background-image: url('#{@base_url}/storage/images/raw/abc123.jpg')"></div>
              </div>
            </a>
            <div class="thumb_attr chapter-title text-truncate" title="Chapter 20">
              <a href="https://manhwa18.net/manga/solo-max-level-newbie/chapter-20-291" title="Chapter 20">Chapter 20</a>
            </div>
            <div class="thumb_attr series-title">
              <a href="https://manhwa18.net/manga/solo-max-level-newbie" title="Solo Max-Level Newbie">Solo Max-Level Newbie</a>
            </div>
          </div>
        </div>
        <div class="thumb-item-flow col-6 col-md-2">
          <div class="thumb-wrapper" data-id="500">
            <a href="https://manhwa18.net/manga/solo-login-manhwa">
              <div class="a6-ratio">
                <div class="content img-in-ratio" data-bg="#{@base_url}/storage/images/raw/def456.jpg"
                     style="background-image: url('#{@base_url}/storage/images/raw/def456.jpg')"></div>
              </div>
            </a>
            <div class="thumb_attr chapter-title text-truncate" title="Chapter 10">
              <a href="https://manhwa18.net/manga/solo-login-manhwa/chapter-10-100" title="Chapter 10">Chapter 10</a>
            </div>
            <div class="thumb_attr series-title">
              <a href="https://manhwa18.net/manga/solo-login-manhwa" title="Solo Login Manhwa">Solo Login Manhwa</a>
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
      <head>
        <meta property="og:image" content="#{@base_url}/storage/images/raw/og-cover.jpg">
      </head>
      <body>
        <div class="top-part">
          <div class="left-column">
            <div class="series-cover">
              <div class="a6-ratio">
                <div class="content img-in-ratio" data-bg="#{@base_url}/storage/images/raw/cover123.jpg"
                     style="background-image: url('#{@base_url}/storage/images/raw/cover123.jpg')"></div>
              </div>
            </div>
          </div>
          <div class="col-12 col-md-8">
            <div class="series-name-group">
              <span class="series-name">
                <a href="https://manhwa18.net/manga/solo-max-level-newbie">Solo Max-Level Newbie</a>
              </span>
            </div>
            <div class="series-information">
              <div class="info-item">
                <span class="info-name">Other name:</span>
                <span class="info-value"> Solo Max-Level Newbie manhwa </span>
              </div>
              <div class="info-item">
                <span class="info-name">Genre:</span>
                <span class="info-value">
                  <a href="https://manhwa18.net/genre/manhwa"><span class="badge badge-info bg-ojisan mx-1"> Manhwa </span></a>
                  <a href="https://manhwa18.net/genre/action"><span class="badge badge-info bg-ojisan mx-1"> Action </span></a>
                </span>
              </div>
              <div class="info-item">
                <span class="info-name">Status:</span>
                <span class="info-value"><a href="/tinh-trang-on-going">On going</a></span>
              </div>
            </div>
          </div>
        </div>
        <div class="summary-wrapper">
          <div class="series-summary">
            <div class="summary-content">
              <p>Jinhyuk, a gaming Nutuber, was the only person who saw the ending of the game.</p>
            </div>
          </div>
        </div>
        <ul class="list-chapters at-series">
          <a href="https://manhwa18.net/manga/solo-max-level-newbie/chapter-3-322" title="Chapter 3">
            <li>
              <div class="chapter-name text-truncate"> Chapter 3 </div>
              <div class="chapter-time">649 view - 05/11/2021</div>
            </li>
          </a>
          <a href="https://manhwa18.net/manga/solo-max-level-newbie/chapter-2-320" title="Chapter 2">
            <li>
              <div class="chapter-name text-truncate"> Chapter 2 </div>
              <div class="chapter-time">1005 view - 05/11/2021</div>
            </li>
          </a>
          <a href="https://manhwa18.net/manga/solo-max-level-newbie/chapter-1-319" title="Chapter 1">
            <li>
              <div class="chapter-name text-truncate"> Chapter 1 </div>
              <div class="chapter-time">1268 view - 05/11/2021</div>
            </li>
          </a>
        </ul>
      </body>
      </html>
    HTML
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Max-Level Newbie - Chapter 1</title></head>
      <body>
        <div id="chapter-content">
          <img class="lazy" data-src="https://cdn.manhwa18.com/f/files/2021-11-05/page1.jpg">
          <img class="lazy" data-src="https://cdn.manhwa18.com/f/files/2021-11-05/page2.jpg">
          <img class="lazy" data-src="https://cdn.manhwa18.com/f/files/2021-11-05/page3.jpg">
        </div>
      </body>
      </html>
    HTML
  end

  def browse_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="thumb-item-flow col-6 col-md-3">
          <div class="thumb-wrapper" data-id="842">
            <a href="https://manhwa18.net/manga/solo-max-level-newbie">
              <div class="a6-ratio">
                <div class="content img-in-ratio" data-bg="#{@base_url}/storage/images/raw/cover123.jpg"></div>
              </div>
            </a>
            <div class="thumb_attr chapter-title text-truncate">
              <a href="https://manhwa18.net/manga/solo-max-level-newbie/chapter-20-291">Chapter 20</a>
            </div>
            <div class="thumb_attr series-title">
              <a href="https://manhwa18.net/manga/solo-max-level-newbie" title="Solo Max-Level Newbie">Solo Max-Level Newbie</a>
            </div>
          </div>
        </div>
        <div class="thumb-item-flow col-6 col-md-3">
          <div class="thumb-wrapper" data-id="100">
            <a href="https://manhwa18.net/manga/another-manhwa">
              <div class="a6-ratio">
                <div class="content img-in-ratio" data-bg="#{@base_url}/storage/images/raw/cover456.jpg"></div>
              </div>
            </a>
            <div class="thumb_attr chapter-title text-truncate">
              <a href="https://manhwa18.net/manga/another-manhwa/chapter-50-200">Chapter 50</a>
            </div>
            <div class="thumb_attr series-title">
              <a href="https://manhwa18.net/manga/another-manhwa" title="Another Manhwa">Another Manhwa</a>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def pages_with_junk_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div id="chapter-content">
          <img src="#{@base_url}/images/logo.png">
          <img src="#{@base_url}/images/favicon.ico">
          <img class="lazy" data-src="https://cdn.manhwa18.com/f/files/2021-11-05/real-page1.jpg">
          <img class="lazy" data-src="https://cdn.manhwa18.com/f/files/2021-11-05/real-page2.jpg">
        </div>
      </body>
      </html>
    HTML
  end

  def pages_webp_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div id="chapter-content">
          <img class="lazy" data-src="https://cdn.manhwa18.com/f/files/2021-11-05/page1.webp">
        </div>
      </body>
      </html>
    HTML
  end
end
