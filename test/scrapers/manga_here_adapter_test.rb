require "test_helper"
require "json"
require "uri"

class MangaHereAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = normalize_uri(build_uri(path_or_url, params))
      key = "GET #{uri}"
      # Try exact match first, then without query string
      body = @mapping[key]
      unless body
        fallback = uri.dup
        fallback.query = nil
        body = @mapping["GET #{fallback}"]
      end
      unless body
        # Try matching just the path
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

    def normalize_uri(uri)
      return uri if uri.query.nil?

      params = URI.decode_www_form(uri.query).sort_by { |pair| pair.join }
      uri.query = URI.encode_www_form(params)
      uri
    end
  end

  def setup
    @base_url = "https://www.mangahere.cc"
    @series_slug = "one_piece"
    @fixtures = {
      "GET #{@base_url}/search" => search_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/" => series_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/c001/1.html" => chapter_page_fixture,
      "GET #{@base_url}/manga/#{@series_slug}/c001/chapterfun.ashx" => chapterfun_fixture,
      "GET #{@base_url}/directory/1.htm" => browse_fixture,
      "GET #{@base_url}/directory/1.htm?latest" => browse_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::MangaHere::Adapter.new(config: { "base_url" => @base_url }, http: @http)
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
      assert result.url.start_with?("#{@base_url}/manga/")
    end
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaHere::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("one piece")

    assert_empty results
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "One Piece", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Adventure"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_author
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_equal "Oda Eiichiro", series.author
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series.cover_url
    assert_match %r{cover}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series.description
    assert_includes series.description, "pirate"
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "One Piece", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaHere::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

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
      assert chapter.url.start_with?("#{@base_url}/manga/")
    end
  end

  def test_chapters_extracts_volume
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    vol_chapter = chapters.find { |ch| ch.volume.present? }

    assert_not_nil vol_chapter
    assert_equal "98", vol_chapter.volume
  end

  def test_chapters_parses_date
    chapters = @adapter.chapters("#{@base_url}/manga/#{@series_slug}/")

    dated_chapter = chapters.find { |ch| ch.published_at.present? }

    assert_not_nil dated_chapter
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaHere::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/manga/nonexistent/")

    assert_empty result
  end

  # --- Pages Tests ---

  def test_pages_returns_results
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/c001/1.html")

    assert_operator pages.size, :>, 0
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/c001/1.html")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/c001/1.html")

    pages.each do |page|
      assert page.url.start_with?("https://")
    end
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/manga/#{@series_slug}/c001/1.html")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaHere::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/manga/nonexistent/c001/1.html")

    assert_empty result
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert_predicate @adapter, :supports_browse?
  end

  def test_browse_returns_browse_results
    results = @adapter.browse(sort: "popular", page: 1)

    assert_operator results.size, :>, 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_latest
    results = @adapter.browse(sort: "latest", page: 1)

    assert_operator results.size, :>, 0
  end

  def test_browse_extracts_titles
    results = @adapter.browse(sort: "popular", page: 1)

    results.each do |result|
      assert_predicate result.title, :present?
    end
  end

  # --- Dean Edwards Unpacker Tests ---

  def test_dean_edwards_unpacker
    # Simple packed JS: var x="hello";
    # Packed with radix 10, keywords: ["var","x","hello"]
    packed = "eval(function(p,a,c,k,e,d){e=function(c){return c};if(!''.replace(/^/,String)){while(c--)d[c]=k[c]||c;k=[function(e){return d[e]}];e=function(){return'\\\\w+'};c=1};while(c--)if(k[c])p=p.replace(new RegExp('\\\\b'+e(c)+'\\\\b','g'),k[c]);return p}('0 1=\"2\";',3,3,'var|x|hello'.split('|')))"

    result = @adapter.send(:unpack_dean_edwards, packed)

    assert_not_nil result
    assert_includes result, "hello"
  end

  # --- Private Method Tests (via public interface) ---

  def test_normalize_url_from_full_url
    series = @adapter.series("#{@base_url}/manga/#{@series_slug}/")

    assert_not_nil series
    assert_equal "One Piece", series.title
  end

  def test_normalize_url_from_slug
    series = @adapter.series(@series_slug)

    assert_not_nil series
    assert_equal "One Piece", series.title
  end

  private

  def search_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Search - MangaHere</title></head>
      <body>
        <ul class="manga-list-4-list">
          <li>
            <p class="manga-list-4-item-title">
              <a href="/manga/#{@series_slug}/" title="One Piece">One Piece</a>
            </p>
            <img class="manga-list-4-cover" src="https://www.mangahere.cc/media/cover-one-piece.jpg" />
          </li>
          <li>
            <p class="manga-list-4-item-title">
              <a href="/manga/one_piece_party/" title="One Piece Party">One Piece Party</a>
            </p>
            <img class="manga-list-4-cover" src="https://www.mangahere.cc/media/cover-opp.jpg" />
          </li>
        </ul>
      </body>
      </html>
    HTML
  end

  def series_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece - MangaHere</title></head>
      <body>
        <div class="detail-info">
          <img class="detail-info-cover-img" src="https://www.mangahere.cc/media/cover-one-piece.jpg" />
          <span class="detail-info-right-title-font">One Piece</span>
          <span class="detail-info-right-title-tip">Ongoing</span>
          <p class="detail-info-right-say">
            <a href="/author/oda+eiichiro">Oda Eiichiro</a>
          </p>
          <p class="detail-info-right-tag-list">
            <a href="/genre/action">Action</a>
            <a href="/genre/adventure">Adventure</a>
            <a href="/genre/comedy">Comedy</a>
          </p>
          <p class="fullcontent">
            Gol D. Roger was known as the "Pirate King," the strongest and most
            infamous being to have sailed the Grand Line. A young pirate named
            Monkey D. Luffy sets out on his adventure.
          </p>
        </div>

        <ul class="detail-main-list">
          <li>
            <a href="/manga/#{@series_slug}/v98/c003/1.html">
              <p class="title3">Vol.98 Ch.003</p>
              <p class="title2">Feb 06,2026</p>
            </a>
          </li>
          <li>
            <a href="/manga/#{@series_slug}/c002/1.html">
              <p class="title3">Ch.002</p>
              <p class="title2">Jan 15,2026</p>
            </a>
          </li>
          <li>
            <a href="/manga/#{@series_slug}/c001/1.html">
              <p class="title3">Ch.001</p>
              <p class="title2">Jan 01,2026</p>
            </a>
          </li>
        </ul>
      </body>
      </html>
    HTML
  end

  def chapter_page_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>One Piece Ch.001 - MangaHere</title></head>
      <body>
        <script>var chapterid = 1459766;</script>
        <script>
          eval(function(p,a,c,k,e,d){e=function(c){return c};if(!''.replace(/^/,String)){while(c--)d[c]=k[c]||c;k=[function(e){return d[e]}];e=function(){return'\\w+'};c=1};while(c--)if(k[c])p=p.replace(new RegExp('\\b'+e(c)+'\\b','g'),k[c]);return p}('0 1=\"2\";',3,3,'var|dm5_key|abc123'.split('|')))
        </script>
        <div class="pager-list-left">
          <span>
            <a data-page="1">1</a>
            <a data-page="2">2</a>
            <a data-page="3">3</a>
            <a>Next</a>
          </span>
        </div>
      </body>
      </html>
    HTML
  end

  def chapterfun_fixture
    # Packed JS that decodes to: var pix="//fmcdn.mangahere.com/store/manga/106/001/compressed/";var pvalue=["b001.jpg"];
    "eval(function(p,a,c,k,e,d){e=function(c){return c};if(!''.replace(/^/,String)){while(c--)d[c]=k[c]||c;k=[function(e){return d[e]}];e=function(){return'\\w+'};c=1};while(c--)if(k[c])p=p.replace(new RegExp('\\b'+e(c)+'\\b','g'),k[c]);return p}('0 1=\"//5.6.7/8/9/a/b/c/\";0 2=[\"3.4\"];',13,13,'var|pix|pvalue|b001|jpg|fmcdn|mangahere|com|store|manga|106|001|compressed'.split('|')))"
  end

  def browse_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Manga Directory - MangaHere</title></head>
      <body>
        <ul class="manga-list-1-list">
          <li>
            <a href="/manga/#{@series_slug}/" title="One Piece">
              <img class="manga-list-1-cover" src="https://www.mangahere.cc/media/cover-one-piece.jpg" />
            </a>
          </li>
          <li>
            <a href="/manga/naruto/" title="Naruto">
              <img class="manga-list-1-cover" src="https://www.mangahere.cc/media/cover-naruto.jpg" />
            </a>
          </li>
        </ul>
      </body>
      </html>
    HTML
  end
end
