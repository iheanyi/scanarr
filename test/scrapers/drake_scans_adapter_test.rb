require "test_helper"
require "uri"

class DrakeScansAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://drakecomic.org"
    @series_slug = "logging-10000-years-into-the-future"
    @chapter_slug = "chapter-100"
    @fixtures = {
      "GET #{@base_url}/manga/?page=1&title=logging" => search_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/" => series_fixture,
      "GET #{@base_url}/logging-10000-years-into-the-future-chapter-100/" => pages_fixture,
      "GET #{@base_url}/manga/?order=update&page=1" => browse_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::DrakeScans::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("logging")

    assert_equal 2, results.size
    assert_equal "Logging 10,000 Years into the Future", results.first.title
    assert_equal @series_slug, results.first.id
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("logging")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("logging")

    assert_not_nil results.first.cover_url
    assert_match %r{https://}, results.first.cover_url
  end

  def test_search_builds_full_urls
    results = @adapter.search("logging")

    results.each do |result|
      assert result.url.start_with?(@base_url)
    end
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::DrakeScans::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("logging")

    assert_equal [], results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Logging 10,000 Years into the Future", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Fantasy"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Do Yeon-woo", series.author
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series.cover_url
    assert_match %r{cover}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series.description
    assert_includes series.description, "awakens"
  end

  def test_series_detects_manhwa_type
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "manhwa", series.series_type
  end

  def test_series_extracts_alt_titles
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_includes series.alt_titles, "10000 Years into the Future"
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "Logging 10,000 Years into the Future", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::DrakeScans::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/manga/nonexistent/")

    assert_nil result
  end

  # --- Chapters Tests ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    assert_equal 3, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_extracts_numbers
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    numbers = chapters.map(&:number).map(&:to_f)
    assert_includes numbers, 98.0
    assert_includes numbers, 99.0
    assert_includes numbers, 100.0
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    numbers = chapters.map { |ch| ch.number.to_f }
    assert_equal numbers.sort, numbers
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    chapters.each do |chapter|
      assert chapter.url.start_with?(@base_url)
    end
  end

  def test_chapters_extracts_group
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    chapters.each do |chapter|
      assert_equal "Drake Scans", chapter.group
    end
  end

  def test_chapters_extracts_release_date
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    dated_chapter = chapters.find { |ch| ch.published_at.present? }
    assert_not_nil dated_chapter
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::DrakeScans::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/manga/nonexistent/")

    assert_equal [], result
  end

  # --- Pages Tests ---

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/logging-10000-years-into-the-future-chapter-100/")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/logging-10000-years-into-the-future-chapter-100/")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/logging-10000-years-into-the-future-chapter-100/")

    pages.each do |page|
      assert page.url.start_with?("https://")
      assert page.url.match?(/\.(jpg|jpeg|png|webp)/i)
    end
  end

  def test_pages_strips_jetpack_cdn_prefix
    pages = @adapter.pages("#{@base_url}/logging-10000-years-into-the-future-chapter-100/")

    pages.each do |page|
      refute_match(/i\d\.wp\.com/, page.url, "Jetpack CDN prefix should be stripped")
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/logging-10000-years-into-the-future-chapter-100/")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::DrakeScans::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/some-series-chapter-999/")

    assert_equal [], result
  end

  # --- Pages JS Fallback Tests ---

  def test_pages_falls_back_to_js_images
    js_fixture = {
      "GET #{@base_url}/some-series-chapter-1/" => pages_js_fallback_fixture
    }
    http = FakeHttpClient.new(mapping: js_fixture, base_url: @base_url)
    adapter = Scrapers::DrakeScans::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/some-series-chapter-1/")

    assert_equal 2, pages.size
    assert_match %r{https://drakecomic\.org}, pages.first.url
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert @adapter.supports_browse?
  end

  def test_browse_returns_results
    results = @adapter.browse(sort: "latest", page: 1)

    assert results.size > 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_result_has_title
    results = @adapter.browse(sort: "latest", page: 1)

    results.each do |result|
      assert result.title.present?
    end
  end

  # --- Jetpack CDN Stripping Tests ---

  def test_strip_jetpack_cdn
    adapter = Scrapers::DrakeScans::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    # Use send to test private method
    assert_equal "https://drakecomic.org/wp-content/uploads/image.jpg",
                 adapter.send(:strip_jetpack_cdn, "https://i0.wp.com/drakecomic.org/wp-content/uploads/image.jpg")
    assert_equal "https://drakecomic.org/wp-content/uploads/image.jpg",
                 adapter.send(:strip_jetpack_cdn, "https://i3.wp.com/drakecomic.org/wp-content/uploads/image.jpg")
    # Non-Jetpack URLs should be unchanged
    assert_equal "https://drakecomic.org/wp-content/uploads/image.jpg",
                 adapter.send(:strip_jetpack_cdn, "https://drakecomic.org/wp-content/uploads/image.jpg")
  end

  # --- Normalize URL Tests ---

  def test_normalize_series_url_from_full_url
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series
    assert_equal "Logging 10,000 Years into the Future", series.title
  end

  def test_normalize_series_url_from_slug
    series = @adapter.series(@series_slug)

    assert_not_nil series
    assert_equal "Logging 10,000 Years into the Future", series.title
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Manga List - Drake Scans</title></head>
      <body>
        <div class="listupd">
          <div class="bs">
            <div class="bsx">
              <a href="#{@base_url}/manga/#{@series_slug}/" title="Logging 10,000 Years into the Future">
                <div class="limit">
                  <img src="https://drakecomic.org/wp-content/uploads/2024/cover-logging.jpg" alt="Logging 10,000 Years into the Future" />
                </div>
              </a>
            </div>
          </div>
          <div class="bs">
            <div class="bsx">
              <a href="#{@base_url}/manga/the-great-mage-returns/" title="The Great Mage Returns After 4000 Years">
                <div class="limit">
                  <img src="https://drakecomic.org/wp-content/uploads/2024/cover-mage.jpg" alt="The Great Mage Returns" />
                </div>
              </a>
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
      <head><title>Logging 10,000 Years into the Future - Drake Scans</title></head>
      <body>
        <div class="bigcontent">
          <h1 class="entry-title">Logging 10,000 Years into the Future</h1>
          <div class="thumb">
            <img src="https://drakecomic.org/wp-content/uploads/2024/cover-logging.jpg" alt="Logging" />
          </div>
          <div class="infotable">
            <tr><td>Author</td><td>Do Yeon-woo</td></tr>
            <tr><td>Artist</td><td>Kim Jae-hwan</td></tr>
            <tr><td>Status</td><td>Ongoing</td></tr>
            <tr><td>Type</td><td>Manhwa</td></tr>
          </div>
          <span class="alternative">10000 Years into the Future; Logging 1만년 후로</span>
          <div class="mgen">
            <a href="/genres/action/">Action</a>
            <a href="/genres/fantasy/">Fantasy</a>
            <a href="/genres/adventure/">Adventure</a>
          </div>
          <div class="desc">
            <p>A hero awakens in a world 10,000 years in the future to find everything has changed.</p>
          </div>
          <div id="chapterlist">
            <ul>
              <li>
                <div class="chbox"></div>
                <div class="eph-num">
                  <a href="#{@base_url}/logging-10000-years-into-the-future-chapter-100/">
                    <span class="chapternum">Chapter 100</span>
                    <span class="chapterdate">January 15, 2025</span>
                  </a>
                </div>
              </li>
              <li>
                <div class="chbox"></div>
                <div class="eph-num">
                  <a href="#{@base_url}/logging-10000-years-into-the-future-chapter-99/">
                    <span class="chapternum">Chapter 99</span>
                    <span class="chapterdate">January 08, 2025</span>
                  </a>
                </div>
              </li>
              <li>
                <div class="chbox"></div>
                <div class="eph-num">
                  <a href="#{@base_url}/logging-10000-years-into-the-future-chapter-98/">
                    <span class="chapternum">Chapter 98</span>
                    <span class="chapterdate">January 01, 2025</span>
                  </a>
                </div>
              </li>
            </ul>
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
      <head><title>Logging 10,000 Years Chapter 100 - Drake Scans</title></head>
      <body>
        <div id="readerarea">
          <img src="https://i0.wp.com/drakecomic.org/wp-content/uploads/WP-manga/data/manga_id/ch100/page-001.jpg" />
          <img src="https://i2.wp.com/drakecomic.org/wp-content/uploads/WP-manga/data/manga_id/ch100/page-002.jpg" />
          <img src="https://i1.wp.com/drakecomic.org/wp-content/uploads/WP-manga/data/manga_id/ch100/page-003.webp" />
        </div>
      </body>
      </html>
    HTML
  end

  def pages_js_fallback_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Some Series Chapter 1 - Drake Scans</title></head>
      <body>
        <div id="readerarea">
          <!-- No img tags -->
        </div>
        <script>
          var ts_reader = {"images": ["https:\\/\\/drakecomic.org\\/wp-content\\/uploads\\/page-001.jpg", "https:\\/\\/drakecomic.org\\/wp-content\\/uploads\\/page-002.jpg"]};
        </script>
      </body>
      </html>
    HTML
  end

  def browse_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Manga List - Drake Scans</title></head>
      <body>
        <div class="listupd">
          <div class="bs">
            <div class="bsx">
              <a href="#{@base_url}/manga/#{@series_slug}/" title="Logging 10,000 Years into the Future">
                <div class="limit">
                  <img src="https://drakecomic.org/wp-content/uploads/2024/cover-logging.jpg" alt="Logging" />
                </div>
              </a>
            </div>
          </div>
          <div class="bs">
            <div class="bsx">
              <a href="#{@base_url}/manga/the-great-mage-returns/" title="The Great Mage Returns After 4000 Years">
                <div class="limit">
                  <img src="https://drakecomic.org/wp-content/uploads/2024/cover-mage.jpg" alt="Mage" />
                </div>
              </a>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end
