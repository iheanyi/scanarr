require "test_helper"
require "uri"

class MangaReadAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://www.mangaread.org"
    @series_slug = "solo-leveling"
    @chapter_slug = "chapter-1"
    @fixtures = {
      "GET #{@base_url}/?post_type=wp-manga&s=solo+leveling" => search_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/" => series_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/" => pages_fixture,
      "GET #{@base_url}/manga/?m_orderby=latest" => browse_fixture_html
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = MangaRead::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("solo leveling")

    assert_equal 2, results.size
    assert_equal "Solo Leveling", results.first.title
    assert_equal @series_slug, results.first.id
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("solo leveling")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("solo leveling")

    assert_not_nil results.first.cover_url
    assert_match %r{https://}, results.first.cover_url
  end

  def test_search_builds_full_urls
    results = @adapter.search("solo leveling")

    results.each do |result|
      assert result.url.start_with?(@base_url)
    end
  end

  def test_search_extracts_author
    results = @adapter.search("solo leveling")

    assert_equal "Chugong", results.first.author
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaRead::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("solo leveling")

    assert_equal [], results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Solo Leveling", series.title
    assert_equal "completed", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Fantasy"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Chugong", series.author
  end

  def test_series_extracts_artist
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Dubu (Redice Studio)", series.artist
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series.cover_url
    assert_match %r{cover}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series.description
    assert_includes series.description, "hunter"
  end

  def test_series_detects_manhwa_type
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "manhwa", series.series_type
  end

  def test_series_extracts_alt_titles
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_includes series.alt_titles, "Na Honjaman Level Up"
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "Solo Leveling", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaRead::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/manga/nonexistent/")

    assert_nil result
  end

  # --- Chapters Tests (AJAX) ---

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

  def test_chapters_extracts_group
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    chapters.each do |chapter|
      assert_equal "MangaRead", chapter.group
    end
  end

  def test_chapters_extracts_release_date
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    dated_chapter = chapters.find { |ch| ch.published_at.present? }
    assert_not_nil dated_chapter
  end

  def test_chapters_loads_via_ajax_when_available
    ajax_fixtures = {
      "POST #{@base_url}/wp-admin/admin-ajax.php" => ajax_chapters_fixture
    }
    http = FakeHttpClient.new(mapping: ajax_fixtures, base_url: @base_url)
    adapter = MangaRead::Adapter.new(config: { "base_url" => @base_url }, http: http)

    chapters = adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    assert_equal 3, chapters.size
    assert_equal "1", chapters.first.number
  end

  def test_chapters_falls_back_to_inline_when_ajax_empty
    # No AJAX mapping, only series page with inline chapters (default setup)
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    assert_equal 3, chapters.size
    assert_equal "1", chapters.first.number
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaRead::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/manga/nonexistent/")

    assert_equal [], result
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
      assert page.url.match?(/\.(jpg|jpeg|png|webp)/i)
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_detects_correct_mime_types
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/")

    assert_equal "image/jpeg", pages[0].mime_type
    assert_equal "image/png", pages[1].mime_type
    assert_equal "image/webp", pages[2].mime_type
  end

  def test_pages_uses_data_lazy_src_fallback
    lazy_fixture = {
      "GET #{@base_url}/manga/#{@series_slug}/chapter-lazy/" => pages_lazy_src_fixture
    }
    http = FakeHttpClient.new(mapping: lazy_fixture, base_url: @base_url)
    adapter = MangaRead::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/manga/#{@series_slug}/chapter-lazy/")

    assert_equal 2, pages.size
    assert_match %r{page-001\.jpg}, pages.first.url
  end

  def test_pages_sequential_indexes
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/#{@chapter_slug}/")

    pages.each_with_index do |page, idx|
      assert_equal idx, page.index
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = MangaRead::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/manga/solo-leveling/chapter-999/")

    assert_equal [], result
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert @adapter.supports_browse?
  end

  def test_browse_sort_options
    assert_equal %w[latest popular], @adapter.browse_sort_options
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

  def test_browse_falls_back_to_html_when_ajax_fails
    # Only HTML fallback mapping, no AJAX
    fallback_fixtures = {
      "GET #{@base_url}/manga/?m_orderby=latest" => browse_fixture_html
    }
    http = FakeHttpClient.new(mapping: fallback_fixtures, base_url: @base_url)
    adapter = MangaRead::Adapter.new(config: { "base_url" => @base_url }, http: http)

    results = adapter.browse(sort: "latest", page: 1)

    assert results.size > 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  # --- Normalize URL Tests ---

  def test_normalize_series_url_from_full_url
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series
    assert_equal "Solo Leveling", series.title
  end

  def test_normalize_series_url_from_slug
    series = @adapter.series(@series_slug)

    assert_not_nil series
    assert_equal "Solo Leveling", series.title
  end

  def test_normalize_series_url_from_path
    series = @adapter.series("/manga/#{@series_slug}/")

    assert_not_nil series
    assert_equal "Solo Leveling", series.title
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Search - MangaRead</title></head>
      <body>
        <div class="c-tabs-item__content">
          <div class="tab-thumb">
            <a href="#{@base_url}/manga/#{@series_slug}/">
              <img src="https://www.mangaread.org/wp-content/uploads/2020/cover-solo-leveling.jpg" alt="Solo Leveling" />
            </a>
          </div>
          <div class="post-title">
            <h3><a href="#{@base_url}/manga/#{@series_slug}/">Solo Leveling</a></h3>
          </div>
          <div class="mg_author">
            <span class="summary-content"><a href="/manga-author/chugong/">Chugong</a></span>
          </div>
        </div>
        <div class="c-tabs-item__content">
          <div class="tab-thumb">
            <a href="#{@base_url}/manga/solo-leveling-ragnarok/">
              <img src="https://www.mangaread.org/wp-content/uploads/2023/cover-slr.jpg" alt="Solo Leveling: Ragnarok" />
            </a>
          </div>
          <div class="post-title">
            <h3><a href="#{@base_url}/manga/solo-leveling-ragnarok/">Solo Leveling: Ragnarok</a></h3>
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
      <head><title>Solo Leveling - MangaRead</title></head>
      <body>
        <div class="post-title">
          <h1>Solo Leveling</h1>
        </div>
        <div class="summary_image">
          <img src="https://www.mangaread.org/wp-content/uploads/2020/cover-solo-leveling.jpg" alt="Solo Leveling" />
        </div>
        <div class="author-content">
          <a href="/manga-author/chugong/">Chugong</a>
        </div>
        <div class="artist-content">
          <a href="/manga-artist/dubu/">Dubu (Redice Studio)</a>
        </div>
        <div class="post-content_item">
          <div class="summary-heading"><h5>Alternative</h5></div>
          <div class="summary-content alternative-title">Na Honjaman Level Up; Only I Level Up</div>
        </div>
        <div class="post-status">
          <div class="summary-heading"><h5>Status</h5></div>
          <div class="summary-content">Completed</div>
        </div>
        <div class="genres-content">
          <a href="/manga-genre/action/">Action</a>
          <a href="/manga-genre/fantasy/">Fantasy</a>
          <a href="/manga-genre/manhwa/">Manhwa</a>
          <a href="/manga-genre/adventure/">Adventure</a>
        </div>
        <div class="description-summary">
          <div class="summary__content">
            In a world where awakened beings called "hunters" must battle deadly
            monsters to protect humanity, Sung Jinwoo is the weakest hunter of all.
            But after a mysterious incident, he alone receives the power to level up.
          </div>
        </div>
        <ul class="main version-chap no-volumn">
          <li class="wp-manga-chapter">
            <a href="#{@base_url}/manga/#{@series_slug}/chapter-3/">Chapter 3</a>
            <span class="chapter-release-date"><i>01/15/24</i></span>
          </li>
          <li class="wp-manga-chapter">
            <a href="#{@base_url}/manga/#{@series_slug}/chapter-2/">Chapter 2</a>
            <span class="chapter-release-date"><i>01/10/24</i></span>
          </li>
          <li class="wp-manga-chapter">
            <a href="#{@base_url}/manga/#{@series_slug}/chapter-1/">Chapter 1</a>
            <span class="chapter-release-date"><i>01/05/24</i></span>
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
          <span class="chapter-release-date"><i>01/15/24</i></span>
        </li>
        <li class="wp-manga-chapter">
          <a href="#{@base_url}/manga/#{@series_slug}/chapter-2/">Chapter 2</a>
          <span class="chapter-release-date"><i>01/10/24</i></span>
        </li>
        <li class="wp-manga-chapter">
          <a href="#{@base_url}/manga/#{@series_slug}/chapter-1/">Chapter 1</a>
          <span class="chapter-release-date"><i>01/05/24</i></span>
        </li>
      </ul>
    HTML
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Leveling Chapter 1 - MangaRead</title></head>
      <body>
        <div class="reading-content">
          <div class="page-break">
            <img data-src="https://www.mangaread.org/wp-content/uploads/WP-manga/data/manga_id/ch1/page-001.jpg" src="" />
          </div>
          <div class="page-break">
            <img data-src="https://www.mangaread.org/wp-content/uploads/WP-manga/data/manga_id/ch1/page-002.png" src="" />
          </div>
          <div class="page-break">
            <img data-src="https://www.mangaread.org/wp-content/uploads/WP-manga/data/manga_id/ch1/page-003.webp" src="" />
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def pages_lazy_src_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Chapter Lazy - MangaRead</title></head>
      <body>
        <div class="reading-content">
          <div class="page-break">
            <img data-lazy-src="https://www.mangaread.org/wp-content/uploads/WP-manga/data/manga_id/ch-lazy/page-001.jpg" src="data:image/gif;base64,placeholder" />
          </div>
          <div class="page-break">
            <img data-lazy-src="https://www.mangaread.org/wp-content/uploads/WP-manga/data/manga_id/ch-lazy/page-002.png" src="data:image/gif;base64,placeholder" />
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def browse_fixture_html
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="page-item-detail">
          <h3 class="h5">
            <a href="#{@base_url}/manga/#{@series_slug}/">Solo Leveling</a>
          </h3>
          <img src="https://www.mangaread.org/wp-content/uploads/2020/cover-solo-leveling.jpg" alt="Solo Leveling" />
        </div>
        <div class="page-item-detail">
          <h3 class="h5">
            <a href="#{@base_url}/manga/one-punch-man/">One Punch Man</a>
          </h3>
          <img src="https://www.mangaread.org/wp-content/uploads/2020/cover-opm.jpg" alt="One Punch Man" />
        </div>
      </body>
      </html>
    HTML
  end
end
