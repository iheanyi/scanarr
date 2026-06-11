require "test_helper"
require "uri"

class MangaPillAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://mangapill.com"
    @series_path = "/manga/2/one-piece"
    @chapter_path = "/chapters/2-1117000/one-piece-chapter-1117"
    @search_query_uri = "#{@base_url}/search?q=one%2Bpiece"

    @fixtures = {
      "GET #{@search_query_uri}" => search_fixture,
      "GET #{@base_url}#{@series_path}" => series_fixture,
      "GET #{@base_url}#{@chapter_path}" => pages_fixture,
      "GET #{@base_url}" => homepage_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::MangaPill::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  def test_supports_browse_with_expected_sort_options
    assert_predicate @adapter, :supports_browse?
    assert_equal %w[latest popular], @adapter.browse_sort_options
  end

  def test_search_returns_results
    results = @adapter.search("one piece")

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
    assert_equal "#{@base_url}#{@series_path}", results.first.url
    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_requests_the_configured_base_url_over_the_constant
    moved = "https://mangapill.moved.example"
    http = FakeHttpClient.new(mapping: { "GET #{moved}/search?q=one%2Bpiece" => search_fixture }, base_url: moved)
    adapter = Scrapers::MangaPill::Adapter.new(config: { "base_url" => moved }, http: http)

    results = adapter.search("one piece")

    assert_equal 2, results.size
    assert_equal "#{moved}#{@series_path}", results.first.url
  end

  def test_series_parses_metadata
    series = @adapter.series(@series_path.delete_prefix("/manga/"))

    assert_equal "One Piece", series.title
    assert_equal "Eiichiro Oda", series.author
    assert_equal "Eiichiro Oda", series.artist
    assert_equal "ongoing", series.status
    assert_equal "manga", series.series_type
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Adventure"
    assert_kind_of ResultTypes::Series, series
  end

  def test_chapters_extracts_and_sorts_numbers
    chapters = @adapter.chapters("#{@base_url}#{@series_path}")

    assert_equal 2, chapters.size
    assert_equal "1117", chapters.first.number
    assert_equal "1118", chapters.last.number
    assert_equal "MangaPill", chapters.first.group
    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_pages_filters_non_page_images_and_sets_mime
    pages = @adapter.pages("#{@base_url}#{@chapter_path}")

    assert_equal 2, pages.size
    assert_equal "https://cdn.example.com/manga/one-piece/1117/1.jpg", pages.first.url
    assert_equal "image/jpeg", pages.first.mime_type
    assert_equal "image/webp", pages.last.mime_type
    assert_equal 0, pages.first.index
    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_browse_latest_uses_new_chapters_cards
    results = @adapter.browse(sort: "latest", page: 1, limit: 20)

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
    assert_equal 1117, results.first.chapter_count
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_popular_uses_trending_cards
    results = @adapter.browse(sort: "popular", page: 1, limit: 20)

    assert_equal 2, results.size
    assert_equal "One Piece", results.first.title
    assert_equal "ongoing", results.first.status
    assert_equal "completed", results.last.status
  end

  def test_returns_empty_or_nil_on_error
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaPill::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    assert_empty adapter.search("one piece")
    assert_nil adapter.series(@series_path.delete_prefix("/manga/"))
    assert_empty adapter.chapters(@series_path)
    assert_empty adapter.pages(@chapter_path)
    assert_empty adapter.browse(sort: "latest")
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="grid">
          <div>
            <a href="/manga/2/one-piece">
              <img data-src="https://cdn.example.com/covers/one-piece.jpg" />
              <div class="line-clamp-2">One Piece</div>
            </a>
          </div>
          <div>
            <a href="/manga/3/one-punch-man">
              <img data-src="https://cdn.example.com/covers/one-punch-man.jpg" />
              <div class="line-clamp-2">One Punch Man</div>
            </a>
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
        <h1>One Piece</h1>
        <img data-src="https://cdn.example.com/covers/one-piece.jpg" />
        <div class="summary">Pirate adventure on the Grand Line.</div>
        <div>Author: Eiichiro Oda</div>
        <div>Artist: Eiichiro Oda</div>
        <div>Status: Publishing</div>
        <div>Type: Manga</div>
        <div class="alt-title">One Piece; OP</div>
        <a href="/genre/action">Action</a>
        <a href="/genre/adventure">Adventure</a>

        <a href="/chapters/2-1117000/one-piece-chapter-1117">Chapter 1117</a>
        <a href="/chapters/2-1118000/one-piece-chapter-1118">Chapter 1118</a>
      </body>
      </html>
    HTML
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div id="reader-content">
          <img data-src="https://cdn.example.com/manga/one-piece/1117/1.jpg" />
          <img data-src="https://cdn.example.com/manga/one-piece/1117/2.webp" />
          <img data-src="https://cdn.example.com/assets/logo.png" />
        </div>
      </body>
      </html>
    HTML
  end

  def homepage_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div id="latest-grid">
          <div>
            <a href="/chapters/2-1117000/one-piece-chapter-1117">
              <figure><img data-src="https://cdn.example.com/covers/one-piece.jpg" /></figure>
              <div>#1117</div>
            </a>
            <a href="/manga/2/one-piece">
              <div class="line-clamp-2">One Piece</div>
            </a>
          </div>
          <div>
            <a href="/chapters/3-620000/tower-of-god-chapter-620">
              <figure><img data-src="https://cdn.example.com/covers/tower-of-god.jpg" /></figure>
              <div>#620</div>
            </a>
            <a href="/manga/3/tower-of-god">
              <div class="line-clamp-2">Tower of God</div>
            </a>
          </div>
        </div>

        <div class="trending-root">
          <div class="section-title">
            <h4>Trending Mangas</h4>
          </div>
          <div class="grid grid-cols-2">
            <div>
              <a href="/manga/2/one-piece">
                <figure><img data-src="https://cdn.example.com/covers/one-piece.jpg" /></figure>
                <div class="line-clamp-2">One Piece</div>
              </a>
              <div class="bg-card">Publishing</div>
            </div>
            <div>
              <a href="/manga/4/naruto">
                <figure><img data-src="https://cdn.example.com/covers/naruto.jpg" /></figure>
                <div class="line-clamp-2">Naruto</div>
              </a>
              <div class="bg-card">Finished</div>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end
