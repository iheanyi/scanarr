require "test_helper"
require "uri"

class LikeMangaAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://likemanga.ink"
    @series_slug = "one-piece"
    @chapter_slug = "one-piece-chapter-1094"
    @fixtures = {
      "GET #{@base_url}/?act=searchadvance&f%5Bkeyword%5D=one+piece" => search_fixture,
      "GET #{@base_url}/#{@series_slug}/" => series_fixture,
      "GET #{@base_url}/#{@chapter_slug}/" => pages_token_fixture,
      "GET #{@base_url}/?act=searchadvance&f%5Bsortby%5D=lastest-chap" => browse_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("one piece")

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
    assert_equal @series_slug, results.first.id
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("one piece")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("one piece")

    assert_not_nil results.first.cover_url
    assert_match %r{https://}, results.first.cover_url
  end

  def test_search_builds_full_urls
    results = @adapter.search("one piece")

    results.each do |result|
      assert result.url.start_with?(@base_url)
    end
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("one piece")

    assert_equal [], results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/#{@series_slug}/")

    assert_equal "One Piece", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Adventure"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/#{@series_slug}/")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/#{@series_slug}/")

    assert_equal "Oda Eiichiro", series.author
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/#{@series_slug}/")

    assert_not_nil series.cover_url
    assert_match %r{cover}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/#{@series_slug}/")

    assert_not_nil series.description
    assert_includes series.description, "pirate"
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "One Piece", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/nonexistent/")

    assert_nil result
  end

  # --- Chapters Tests ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/#{@series_slug}/")

    assert_equal 3, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/#{@series_slug}/")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_extracts_numbers
    chapters = @adapter.chapters("#{@base_url}/#{@series_slug}/")

    numbers = chapters.map(&:number).map(&:to_f)
    assert_includes numbers, 1092.0
    assert_includes numbers, 1093.0
    assert_includes numbers, 1094.0
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/#{@series_slug}/")

    numbers = chapters.map { |ch| ch.number.to_f }
    assert_equal numbers.sort, numbers
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/#{@series_slug}/")

    chapters.each do |chapter|
      assert chapter.url.start_with?(@base_url)
    end
  end

  def test_chapters_extracts_group
    chapters = @adapter.chapters("#{@base_url}/#{@series_slug}/")

    chapters.each do |chapter|
      assert_equal "LikeManga", chapter.group
    end
  end

  def test_chapters_extracts_release_date
    chapters = @adapter.chapters("#{@base_url}/#{@series_slug}/")

    dated_chapter = chapters.find { |ch| ch.published_at.present? }
    assert_not_nil dated_chapter
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/nonexistent/")

    assert_equal [], result
  end

  # --- Pages Tests (Token method) ---

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/#{@chapter_slug}/")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/#{@chapter_slug}/")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/#{@chapter_slug}/")

    pages.each do |page|
      assert page.url.start_with?("https://")
      assert page.url.match?(/\.(jpg|jpeg|png|webp)/i)
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/#{@chapter_slug}/")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/some-chapter/")

    assert_equal [], result
  end

  # --- Pages Fallback Tests ---

  def test_pages_falls_back_to_img_tags
    fallback_fixtures = {
      "GET #{@base_url}/#{@chapter_slug}-fallback/" => pages_fallback_fixture
    }
    http = FakeHttpClient.new(mapping: fallback_fixtures, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/#{@chapter_slug}-fallback/")

    assert_equal 2, pages.size
    assert_match %r{https://}, pages.first.url
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

  # --- Normalize URL Tests ---

  def test_normalize_series_url_from_full_url
    series = @adapter.series("#{@base_url}/#{@series_slug}/")

    assert_not_nil series
    assert_equal "One Piece", series.title
  end

  def test_normalize_series_url_from_slug
    series = @adapter.series(@series_slug)

    assert_not_nil series
    assert_equal "One Piece", series.title
  end

  # --- Alt Titles Tests ---

  def test_series_extracts_alt_titles
    series = @adapter.series("#{@base_url}/#{@series_slug}/")

    assert_includes series.alt_titles, "Wan Pisu"
    assert_includes series.alt_titles, "OP"
  end

  # --- Series Type Tests ---

  def test_series_detects_manga_type_by_default
    series = @adapter.series("#{@base_url}/#{@series_slug}/")

    assert_equal "manga", series.series_type
  end

  def test_series_detects_manhwa_type
    manhwa_fixtures = {
      "GET #{@base_url}/solo-leveling/" => series_manhwa_fixture
    }
    http = FakeHttpClient.new(mapping: manhwa_fixtures, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: http)

    series = adapter.series("#{@base_url}/solo-leveling/")

    assert_equal "manhwa", series.series_type
  end

  # --- Chapter Title Tests ---

  def test_chapters_extracts_title_when_present
    title_fixtures = {
      "GET #{@base_url}/titled-series/" => series_with_titled_chapters_fixture
    }
    http = FakeHttpClient.new(mapping: title_fixtures, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: http)

    chapters = adapter.chapters("#{@base_url}/titled-series/")
    titled = chapters.find { |ch| ch.number == "5" }

    assert_equal "The Beginning", titled.title
  end

  def test_chapters_returns_nil_title_when_not_present
    chapters = @adapter.chapters("#{@base_url}/#{@series_slug}/")

    chapters.each do |chapter|
      assert_nil chapter.title
    end
  end

  # --- AJAX Chapter Pagination Tests ---

  def test_chapters_fetches_ajax_pages
    ajax_fixtures = {
      "GET #{@base_url}/#{@series_slug}/" => series_with_pagination_fixture,
      "GET #{@base_url}/?act=ajax&chap_id=0&code=load_list_chapter&keyword=&manga_id=12345&page_num=2" => ajax_chapters_fixture
    }
    http = FakeHttpClient.new(mapping: ajax_fixtures, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: http)

    chapters = adapter.chapters("#{@base_url}/#{@series_slug}/")

    # Should have chapters from both page 1 (3 chapters) and AJAX page 2 (2 chapters)
    assert_equal 5, chapters.size
    numbers = chapters.map { |ch| ch.number.to_f }
    assert_includes numbers, 1090.0
    assert_includes numbers, 1094.0
  end

  # --- Browse Popular Tests ---

  def test_browse_popular_returns_results
    popular_fixtures = {
      "GET #{@base_url}/?act=searchadvance&f%5Bsortby%5D=top-manga" => browse_fixture
    }
    http = FakeHttpClient.new(mapping: popular_fixtures, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: http)

    results = adapter.browse(sort: "popular", page: 1)

    assert results.size > 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_result_includes_cover_url
    results = @adapter.browse(sort: "latest", page: 1)

    results.each do |result|
      assert_not_nil result.cover_url
    end
  end

  def test_browse_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.browse(sort: "latest", page: 1)

    assert_equal [], results
  end

  # --- Pages Token CDN URL Tests ---

  def test_pages_constructs_cdn_urls_from_token
    pages = @adapter.pages("#{@base_url}/#{@chapter_slug}/")

    pages.each do |page|
      assert page.url.start_with?("https://cdn.likemanga.ink/uploads/")
    end
  end

  def test_pages_indexes_start_at_zero
    pages = @adapter.pages("#{@base_url}/#{@chapter_slug}/")

    pages.each_with_index do |page, idx|
      assert_equal idx, page.index
    end
  end

  # --- Status Parsing Tests ---

  def test_status_complete
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    assert_equal "completed", adapter.normalize_status("Complete")
  end

  def test_status_in_process
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    assert_equal "ongoing", adapter.normalize_status("In process")
  end

  def test_status_pause
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    assert_equal "hiatus", adapter.normalize_status("Pause")
  end

  def test_status_unknown_defaults_to_ongoing
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    assert_equal "ongoing", adapter.normalize_status("SomeRandomStatus")
  end

  def test_status_nil_defaults_to_ongoing
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: @http)

    assert_equal "ongoing", adapter.normalize_status(nil)
  end

  # --- Image Attribute Fallback Tests ---

  def test_pages_fallback_handles_data_src_attribute
    fallback_fixtures = {
      "GET #{@base_url}/datasrc-chapter/" => pages_datasrc_fixture
    }
    http = FakeHttpClient.new(mapping: fallback_fixtures, base_url: @base_url)
    adapter = LikeManga::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/datasrc-chapter/")

    assert_equal 2, pages.size
    assert_match %r{https://cdn\.likemanga\.ink}, pages.first.url
  end

  # --- Mime Type Tests ---

  def test_pages_detects_webp_mime_type
    pages = @adapter.pages("#{@base_url}/#{@chapter_slug}/")

    webp_page = pages.find { |p| p.url.end_with?(".webp") }
    assert_not_nil webp_page
    assert_equal "image/webp", webp_page.mime_type
  end

  def test_pages_detects_jpg_mime_type
    pages = @adapter.pages("#{@base_url}/#{@chapter_slug}/")

    jpg_page = pages.find { |p| p.url.end_with?(".jpg") }
    assert_not_nil jpg_page
    assert_equal "image/jpeg", jpg_page.mime_type
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Search - LikeManga</title></head>
      <body>
        <div class="card-body">
          <div class="card">
            <a href="#{@base_url}/#{@series_slug}/">
              <img src="https://likemanga.ink/uploads/cover-one-piece.jpg" alt="One Piece" />
            </a>
            <div class="title-manga">One Piece</div>
          </div>
          <div class="card">
            <a href="#{@base_url}/one-piece-party/">
              <img src="https://likemanga.ink/uploads/cover-opp.jpg" alt="One Piece Party" />
            </a>
            <div class="title-manga">One Piece Party</div>
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
      <head><title>One Piece - LikeManga</title></head>
      <body>
        <h1 id="title-detail-manga" data-manga="12345">One Piece</h1>
        <div class="detail-info">
          <img src="https://likemanga.ink/uploads/cover-one-piece.jpg" alt="One Piece" />
        </div>
        <div id="summary_shortened">
          Gol D. Roger was known as the pirate King, the strongest being to have sailed the Grand Line.
        </div>
        <div class="list-info">
          <div class="author">
            <p>Author:</p>
            <p>Oda Eiichiro</p>
          </div>
          <div class="status">
            <p>Status:</p>
            <p>In process</p>
          </div>
          <a href="/genres/action/">Action</a>
          <a href="/genres/adventure/">Adventure</a>
          <a href="/genres/comedy/">Comedy</a>
        </div>
        <div class="other-name">Wan Pisu; OP</div>
        <div class="list-chapter">
          <div class="wp-manga-chapter">
            <a href="#{@base_url}/one-piece-chapter-1094/">Chapter 1094</a>
            <span class="chapter-release-date">January 15, 2025</span>
          </div>
          <div class="wp-manga-chapter">
            <a href="#{@base_url}/one-piece-chapter-1093/">Chapter 1093</a>
            <span class="chapter-release-date">January 08, 2025</span>
          </div>
          <div class="wp-manga-chapter">
            <a href="#{@base_url}/one-piece-chapter-1092/">Chapter 1092</a>
            <span class="chapter-release-date">January 01, 2025</span>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def pages_token_fixture
    # Build a JWT-like token: header.payload.signature
    # Payload contains {"data": base64(JSON array of image paths)}
    image_paths = [ "chapter-1094/page-001.jpg", "chapter-1094/page-002.jpg", "chapter-1094/page-003.webp" ]
    encoded_images = Base64.strict_encode64(JSON.generate(image_paths))
    payload = { "data" => encoded_images }
    token = "header.#{Base64.strict_encode64(JSON.generate(payload))}.signature"

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece Chapter 1094 - LikeManga</title></head>
      <body>
        <div class="reading">
          <input id="currentlink" value="https://cdn.likemanga.ink/uploads" />
          <input id="next_img_token" value="#{token}" />
        </div>
      </body>
      </html>
    HTML
  end

  def pages_fallback_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece Chapter 1094 - LikeManga</title></head>
      <body>
        <div class="reading-detail box_doc">
          <img src="https://cdn.likemanga.ink/uploads/chapter-1094/page-001.jpg" />
          <img src="https://cdn.likemanga.ink/uploads/chapter-1094/page-002.jpg" />
        </div>
      </body>
      </html>
    HTML
  end

  def browse_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Latest - LikeManga</title></head>
      <body>
        <div class="card-body">
          <div class="card">
            <a href="#{@base_url}/#{@series_slug}/">
              <img src="https://likemanga.ink/uploads/cover-one-piece.jpg" alt="One Piece" />
            </a>
            <div class="title-manga">One Piece</div>
          </div>
          <div class="card">
            <a href="#{@base_url}/naruto/">
              <img src="https://likemanga.ink/uploads/cover-naruto.jpg" alt="Naruto" />
            </a>
            <div class="title-manga">Naruto</div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def series_manhwa_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Leveling - LikeManga</title></head>
      <body>
        <h1 id="title-detail-manga" data-manga="99999">Solo Leveling</h1>
        <div class="detail-info">
          <img src="https://likemanga.ink/uploads/cover-solo-leveling.jpg" alt="Solo Leveling" />
        </div>
        <div id="summary_shortened">
          The weakest hunter of all mankind awakens with the power of the System.
        </div>
        <div class="list-info">
          <div class="author">
            <p>Author:</p>
            <p>Chugong</p>
          </div>
          <div class="status">
            <p>Status:</p>
            <p>Complete</p>
          </div>
          <a href="/genres/action/">Action</a>
          <a href="/genres/manhwa/">Manhwa</a>
          <a href="/genres/fantasy/">Fantasy</a>
        </div>
      </body>
      </html>
    HTML
  end

  def series_with_titled_chapters_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Titled Series - LikeManga</title></head>
      <body>
        <h1 id="title-detail-manga" data-manga="11111">Titled Series</h1>
        <div class="detail-info">
          <img src="https://likemanga.ink/uploads/cover-titled.jpg" alt="Titled" />
        </div>
        <div class="list-info">
          <div class="status">
            <p>Status:</p>
            <p>In process</p>
          </div>
        </div>
        <div class="list-chapter">
          <div class="wp-manga-chapter">
            <a href="#{@base_url}/titled-series-chapter-5/">Chapter 5 - The Beginning</a>
            <span class="chapter-release-date">February 01, 2025</span>
          </div>
          <div class="wp-manga-chapter">
            <a href="#{@base_url}/titled-series-chapter-4/">Chapter 4</a>
            <span class="chapter-release-date">January 25, 2025</span>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def series_with_pagination_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece - LikeManga</title></head>
      <body>
        <h1 id="title-detail-manga" data-manga="12345">One Piece</h1>
        <div class="detail-info">
          <img src="https://likemanga.ink/uploads/cover-one-piece.jpg" alt="One Piece" />
        </div>
        <div class="list-info">
          <div class="status">
            <p>Status:</p>
            <p>In process</p>
          </div>
        </div>
        <div class="list-chapter">
          <div class="wp-manga-chapter">
            <a href="#{@base_url}/one-piece-chapter-1094/">Chapter 1094</a>
            <span class="chapter-release-date">January 15, 2025</span>
          </div>
          <div class="wp-manga-chapter">
            <a href="#{@base_url}/one-piece-chapter-1093/">Chapter 1093</a>
            <span class="chapter-release-date">January 08, 2025</span>
          </div>
          <div class="wp-manga-chapter">
            <a href="#{@base_url}/one-piece-chapter-1092/">Chapter 1092</a>
            <span class="chapter-release-date">January 01, 2025</span>
          </div>
        </div>
        <div class="chapters_pagination">
          <a onclick="load_list_chapter(1)">1</a>
          <a onclick="load_list_chapter(2)">2</a>
        </div>
      </body>
      </html>
    HTML
  end

  def ajax_chapters_fixture
    chapters_html = <<~HTML
      <div class="wp-manga-chapter">
        <a href="#{@base_url}/one-piece-chapter-1091/">Chapter 1091</a>
        <span class="chapter-release-date">December 25, 2024</span>
      </div>
      <div class="wp-manga-chapter">
        <a href="#{@base_url}/one-piece-chapter-1090/">Chapter 1090</a>
        <span class="chapter-release-date">December 18, 2024</span>
      </div>
    HTML

    JSON.generate({ "list_chap" => chapters_html })
  end

  def pages_datasrc_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Chapter with data-src - LikeManga</title></head>
      <body>
        <div class="reading-detail box_doc">
          <img data-src="https://cdn.likemanga.ink/uploads/chapter-1/page-001.jpg" />
          <img data-src="https://cdn.likemanga.ink/uploads/chapter-1/page-002.png" />
        </div>
      </body>
      </html>
    HTML
  end
end
