require "test_helper"
require "uri"

class ManhuaPlusAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://manhuaplus.com"
    @series_slug = "martial-peak"
    @chapter_slug = "chapter-1"
    @fixtures = {
      "GET #{@base_url}/?post_type=wp-manga&s=martial+peak" => search_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/" => series_fixture,
      "POST #{@base_url}/manga/#{@series_slug}/ajax/chapters/" => ajax_chapters_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/" => pages_fixture,
      "POST #{@base_url}/wp-admin/admin-ajax.php" => browse_fixture,
      "GET #{@base_url}/manga/?m_orderby=latest" => browse_fixture_html
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::ManhuaPlus::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("martial peak")

    assert_equal 2, results.size
    assert_equal "Martial Peak", results.first.title
    assert_equal @series_slug, results.first.id
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("martial peak")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("martial peak")

    assert_not_nil results.first.cover_url
    assert_match %r{https://}, results.first.cover_url
  end

  def test_search_builds_full_urls
    results = @adapter.search("martial peak")

    results.each do |result|
      assert result.url.start_with?(@base_url)
    end
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::ManhuaPlus::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("martial peak")

    assert_empty results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Martial Peak", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Martial Arts"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Momo (Ii)", series.author
  end

  def test_series_extracts_artist
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Pikapi", series.artist
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series.cover_url
    assert_match %r{cover}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series.description
    assert_includes series.description, "martial peak"
  end

  def test_series_detects_manhua_type
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "manhua", series.series_type
  end

  def test_series_extracts_alt_titles
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_includes series.alt_titles, "MP"
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "Martial Peak", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::ManhuaPlus::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

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

    assert_includes numbers, 1.0
    assert_includes numbers, 2.0
    assert_includes numbers, 3.0
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

  def test_chapters_extracts_release_date
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    dated_chapter = chapters.find { |ch| ch.published_at.present? }

    assert_not_nil dated_chapter
  end

  def test_chapters_sets_group
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    chapters.each do |chapter|
      assert_equal "ManhuaPlus", chapter.group
    end
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::ManhuaPlus::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/manga/nonexistent/")

    assert_empty result
  end

  # --- Pages Tests ---

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/")

    pages.each do |page|
      assert page.url.start_with?("https://")
      assert_match /\.(jpg|jpeg|png|webp)/i, page.url
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::ManhuaPlus::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/manga/martial-peak/chapter-999/")

    assert_empty result
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
      assert_predicate result.title, :present?
    end
  end

  # --- Date Parsing Tests ---

  def test_parses_full_month_date
    adapter = Scrapers::ManhuaPlus::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    result = adapter.send(:parse_madara_date, "December 22, 2025")

    assert_not_nil result
    assert_equal 2025, result.year
    assert_equal 12, result.month
    assert_equal 22, result.day
  end

  def test_parses_ordinal_date
    adapter = Scrapers::ManhuaPlus::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    result = adapter.send(:parse_madara_date, "January 5th, 2024")

    assert_not_nil result
    assert_equal 2024, result.year
    assert_equal 1, result.month
    assert_equal 5, result.day
  end

  def test_parses_relative_date
    adapter = Scrapers::ManhuaPlus::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    result = adapter.send(:parse_madara_date, "3 days ago")

    assert_not_nil result
    assert_in_delta Time.current - 3.days, result, 5.seconds
  end

  # --- Normalize URL Tests ---

  def test_normalize_series_url_from_full_url
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series
    assert_equal "Martial Peak", series.title
  end

  def test_normalize_series_url_from_slug
    series = @adapter.series(@series_slug)

    assert_not_nil series
    assert_equal "Martial Peak", series.title
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Search - ManhuaPlus</title></head>
      <body>
        <div class="c-tabs-item__content">
          <div class="tab-thumb">
            <a href="#{@base_url}/manga/#{@series_slug}/">
              <img src="https://manhuaplus.com/wp-content/uploads/2020/07/cover-martial-peak.jpg" alt="Martial Peak" />
            </a>
          </div>
          <div class="post-title">
            <h3><a href="#{@base_url}/manga/#{@series_slug}/">Martial Peak</a></h3>
          </div>
          <div class="mg_author">
            <span class="summary-content"><a href="/manga-author/momo-ii/">Momo (Ii)</a></span>
          </div>
        </div>
        <div class="c-tabs-item__content">
          <div class="tab-thumb">
            <a href="#{@base_url}/manga/martial-god-asura/">
              <img src="https://manhuaplus.com/wp-content/uploads/2020/07/cover-mga.jpg" alt="Martial God Asura" />
            </a>
          </div>
          <div class="post-title">
            <h3><a href="#{@base_url}/manga/martial-god-asura/">Martial God Asura</a></h3>
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
      <head><title>Martial Peak - ManhuaPlus</title></head>
      <body>
        <div class="post-title">
          <h1>Martial Peak</h1>
        </div>
        <div class="summary_image">
          <img src="https://manhuaplus.com/wp-content/uploads/2020/07/cover-martial-peak.jpg" alt="Martial Peak" />
        </div>
        <div class="author-content">
          <a href="/manga-author/momo-ii/">Momo (Ii)</a>
        </div>
        <div class="artist-content">
          <a href="/manga-artist/pikapi/">Pikapi</a>
        </div>
        <div class="post-content_item">
          <div class="summary-heading"><h5>Alternative</h5></div>
          <div class="summary-content alternative-title">MP; 武炼巅峰</div>
        </div>
        <div class="post-status">
          <div class="summary-heading"><h5>Status</h5></div>
          <div class="summary-content">OnGoing</div>
        </div>
        <div class="genres-content">
          <a href="/manga-genre/action/">Action</a>
          <a href="/manga-genre/adventure/">Adventure</a>
          <a href="/manga-genre/manhua/">Manhua</a>
          <a href="/manga-genre/martial-arts/">Martial Arts</a>
        </div>
        <div class="description-summary">
          <div class="summary__content">
            The journey to the martial peak is a lonely, solitary and long one.
            In the face of adversity, you must survive and remain unyielding.
          </div>
        </div>
        <ul class="main version-chap no-volumn">
          <li class="wp-manga-chapter">
            <a href="#{@base_url}/manga/#{@series_slug}/chapter-3/">Chapter 3</a>
            <span class="chapter-release-date"><i>December 22, 2025</i></span>
          </li>
          <li class="wp-manga-chapter">
            <a href="#{@base_url}/manga/#{@series_slug}/chapter-2/">Chapter 2</a>
            <span class="chapter-release-date"><i>December 15, 2025</i></span>
          </li>
          <li class="wp-manga-chapter">
            <a href="#{@base_url}/manga/#{@series_slug}/chapter-1/">Chapter 1</a>
            <span class="chapter-release-date"><i>December 10, 2025</i></span>
          </li>
        </ul>
      </body>
      </html>
    HTML
  end

  def ajax_chapters_fixture
    <<~HTML
      <ul class="main version-chap no-volumn">
        <li class="wp-manga-chapter">
          <a href="#{@base_url}/manga/#{@series_slug}/chapter-3/">Chapter 3</a>
          <span class="chapter-release-date"><i>December 22, 2025</i></span>
        </li>
        <li class="wp-manga-chapter">
          <a href="#{@base_url}/manga/#{@series_slug}/chapter-2/">Chapter 2</a>
          <span class="chapter-release-date"><i>December 15, 2025</i></span>
        </li>
        <li class="wp-manga-chapter">
          <a href="#{@base_url}/manga/#{@series_slug}/chapter-1/">Chapter 1</a>
          <span class="chapter-release-date"><i>December 10, 2025</i></span>
        </li>
      </ul>
    HTML
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Martial Peak Chapter 1 - ManhuaPlus</title></head>
      <body>
        <div class="reading-content">
          <div class="page-break">
            <img data-src="https://manhuaplus.com/wp-content/uploads/WP-manga/data/manga_id/ch1/page-001.jpg" src="" />
          </div>
          <div class="page-break">
            <img data-src="https://manhuaplus.com/wp-content/uploads/WP-manga/data/manga_id/ch1/page-002.png" src="" />
          </div>
          <div class="page-break">
            <img data-src="https://manhuaplus.com/wp-content/uploads/WP-manga/data/manga_id/ch1/page-003.webp" src="" />
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def browse_fixture
    <<~HTML
      <div class="page-item-detail">
        <h3 class="h5">
          <a href="#{@base_url}/manga/#{@series_slug}/">Martial Peak</a>
        </h3>
        <img src="https://manhuaplus.com/wp-content/uploads/2020/07/cover-martial-peak.jpg" alt="Martial Peak" />
      </div>
      <div class="page-item-detail">
        <h3 class="h5">
          <a href="#{@base_url}/manga/magic-emperor/">Magic Emperor</a>
        </h3>
        <img src="https://manhuaplus.com/wp-content/uploads/2020/07/cover-magic-emperor.jpg" alt="Magic Emperor" />
      </div>
    HTML
  end

  def browse_fixture_html
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="page-item-detail">
          <h3 class="h5">
            <a href="#{@base_url}/manga/#{@series_slug}/">Martial Peak</a>
          </h3>
          <img src="https://manhuaplus.com/wp-content/uploads/2020/07/cover-martial-peak.jpg" alt="Martial Peak" />
        </div>
      </body>
      </html>
    HTML
  end
end
