require "test_helper"

class ToonilyAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = URI(path_or_url.to_s)
      uri = URI.join(@base_url, path_or_url.to_s) if uri.host.nil?
      # Include query params in the key for differentiation
      query = URI.encode_www_form(params) unless params.empty?
      full_uri = query ? "#{uri}?#{query}" : uri.to_s
      key = "GET #{full_uri}"
      body = @mapping[key] || @mapping["GET #{uri}"]
      status = body ? 200 : 404
      Response.new(status: status, body: body || "", headers: {}, url: full_uri)
    end
  end

  def setup
    @base_url = "https://toonily.me"
    @fixtures = {
      "GET #{@base_url}/api/manga/search?q=solo" => search_fixture,
      "GET #{@base_url}/solo-leveling" => series_fixture,
      "GET #{@base_url}/solo-leveling/chapter-1" => pages_fixture,
      "GET #{@base_url}/az-list?page=1&sort=views" => browse_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Toonily::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # -- Search tests --

  def test_search_returns_results
    results = @adapter.search("solo")

    assert_equal 2, results.size
  end

  def test_search_extracts_title
    results = @adapter.search("solo")

    assert_equal "Solo Leveling", results.first.title
  end

  def test_search_builds_url
    results = @adapter.search("solo")

    assert_equal "#{@base_url}/solo-leveling", results.first.url
  end

  def test_search_extracts_cover_url
    results = @adapter.search("solo")

    assert_equal "https://sb.toonilycdnv2.xyz/thumb/abc123.png", results.first.cover_url
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("solo")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_no_results
    results = @adapter.search("nonexistent manga xyz")

    assert_empty results
  end

  # -- Series tests --

  def test_series_parses_title
    series = @adapter.series("#{@base_url}/solo-leveling")

    assert_equal "Solo Leveling", series.title
  end

  def test_series_parses_alt_titles
    series = @adapter.series("#{@base_url}/solo-leveling")

    assert_includes series.alt_titles, "I Level Up Alone"
  end

  def test_series_parses_author
    series = @adapter.series("#{@base_url}/solo-leveling")

    assert_equal "Chu-Gong", series.author
  end

  def test_series_parses_status
    series = @adapter.series("#{@base_url}/solo-leveling")

    assert_equal "completed", series.status
  end

  def test_series_parses_description
    series = @adapter.series("#{@base_url}/solo-leveling")

    assert_match(/weakest hunter/, series.description)
  end

  def test_series_parses_cover_url
    series = @adapter.series("#{@base_url}/solo-leveling")

    assert_equal "https://sb.toonilycdnv2.xyz/thumb/sl-cover.png", series.cover_url
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/solo-leveling")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_type_is_manhwa
    series = @adapter.series("#{@base_url}/solo-leveling")

    assert_equal "manhwa", series.series_type
  end

  def test_series_returns_nil_for_not_found
    series = @adapter.series("#{@base_url}/nonexistent-manga")

    assert_nil series
  end

  # -- Chapters tests --

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/solo-leveling")

    assert_equal 3, chapters.size
  end

  def test_chapters_extracts_number
    chapters = @adapter.chapters("#{@base_url}/solo-leveling")
    numbers = chapters.map(&:number)

    assert_includes numbers, "1"
    assert_includes numbers, "2"
    assert_includes numbers, "3"
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/solo-leveling")

    assert_equal "1", chapters.first.number
    assert_equal "3", chapters.last.number
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/solo-leveling")

    assert_equal "#{@base_url}/solo-leveling/chapter-1", chapters.first.url
  end

  def test_chapters_sets_group
    chapters = @adapter.chapters("#{@base_url}/solo-leveling")

    assert_equal "Toonily", chapters.first.group
  end

  def test_chapters_parses_date
    chapters = @adapter.chapters("#{@base_url}/solo-leveling")
    ch = chapters.find { |c| c.number == "2" }

    assert_equal Date.new(2023, 6, 20), ch.published_at
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/solo-leveling")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  # -- Pages tests --

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/solo-leveling/chapter-1")

    assert_equal 3, pages.size
  end

  def test_pages_extracts_cdn_urls
    pages = @adapter.pages("#{@base_url}/solo-leveling/chapter-1")

    assert_match(/toonilycdnv2\.xyz/, pages.first.url)
  end

  def test_pages_sets_index
    pages = @adapter.pages("#{@base_url}/solo-leveling/chapter-1")

    assert_equal 0, pages.first.index
    assert_equal 1, pages[1].index
    assert_equal 2, pages[2].index
  end

  def test_pages_detects_mime_type
    pages = @adapter.pages("#{@base_url}/solo-leveling/chapter-1")

    assert_equal "image/jpeg", pages.first.mime_type
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/solo-leveling/chapter-1")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_filters_ad_images
    pages = @adapter.pages("#{@base_url}/solo-leveling/chapter-1")

    pages.each do |page|
      refute_match(/exdynsrv|pemsrv/, page.url)
    end
  end

  # -- Browse tests --

  def test_supports_browse
    assert @adapter.supports_browse?
  end

  def test_browse_returns_results
    results = @adapter.browse(sort: "popular", page: 1)

    assert_equal 2, results.size
  end

  def test_browse_extracts_title
    results = @adapter.browse(sort: "popular", page: 1)

    assert_equal "Solo Leveling", results.first.title
  end

  def test_browse_extracts_cover_url
    results = @adapter.browse(sort: "popular", page: 1)

    assert_equal "https://sb.toonilycdnv2.xyz/thumb/sl-cover.png", results.first.cover_url
  end

  def test_browse_returns_browse_result_structs
    results = @adapter.browse(sort: "popular", page: 1)

    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  private

  def search_fixture
    <<~HTML
      <div class="novel__item">
        <div class="novel__item-inner">
          <div class="novel__item-icon">
            <a title="Solo Leveling" href="/solo-leveling">
              <img src="//sb.toonilycdnv2.xyz/thumb/abc123.png" alt="Solo Leveling">
            </a>
          </div>
          <div class="novel__item-meta">
            <div class="name">
              <h3><a title="Solo Leveling" href="/solo-leveling">Solo Leveling</a></h3>
            </div>
          </div>
        </div>
      </div>
      <div class="novel__item">
        <div class="novel__item-inner">
          <div class="novel__item-icon">
            <a title="Solo Login" href="/solo-login">
              <img src="//sb.toonilycdnv2.xyz/thumb/def456.png" alt="Solo Login">
            </a>
          </div>
          <div class="novel__item-meta">
            <div class="name">
              <h3><a title="Solo Login" href="/solo-login">Solo Login</a></h3>
            </div>
          </div>
        </div>
      </div>
    HTML
  end

  def series_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Leveling</title></head>
      <body>
        <div class="cover box">
          <img class="lazy" data-src="//sb.toonilycdnv2.xyz/thumb/sl-cover.png" alt="Solo Leveling">
        </div>
        <div class="detail">
          <div class="name box">
            <h1>Solo Leveling</h1>
            <h2>I Level Up Alone ; 나 혼자만 레벨업</h2>
          </div>
          <div class="meta box mt-1 p-10">
            <p><strong>Authors :</strong>
              <a href="/authors/chu-gong" title="Chu-Gong">
                <span>Chu-Gong</span>
              </a>
            </p>
            <p><strong>Status :</strong>
              <a href="/status/COMPLETED" title="Read COMPLETED Manga">
                <span>COMPLETED</span>
              </a>
            </p>
            <p><strong>Genres :</strong></p>
            <p><strong>Chapters: </strong> <span>203</span></p>
          </div>
        </div>

        <div class="section box mt-1 summary">
          <div class="section-body">
            <p class="content">The weakest hunter of all mankind, Sung Jin-Woo.</p>
          </div>
        </div>

        <div id="chapters" data-sort="desc">
          <ul class="chapter-list" id="chapter-list">
            <li id="c-3"><a href="/solo-leveling/chapter-3" title="Solo Leveling - Chapter 3">
              <div><strong class="chapter-title">Chapter 3</strong>
              <time class="chapter-update">Jun 20, 2023</time></div>
            </a></li>
            <li id="c-2"><a href="/solo-leveling/chapter-2" title="Solo Leveling - Chapter 2">
              <div><strong class="chapter-title">Chapter 2</strong>
              <time class="chapter-update">Jun 20, 2023</time></div>
            </a></li>
            <li id="c-1"><a href="/solo-leveling/chapter-1" title="Solo Leveling - Chapter 1">
              <div><strong class="chapter-title">Chapter 1</strong>
              <time class="chapter-update">a year ago</time></div>
            </a></li>
          </ul>
        </div>

        <script>
          var bookId = 122;
          var bookSlug = "solo-leveling";
          var chapterId = null;
        </script>
      </body>
      </html>
    HTML
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Solo Leveling Chapter 1</title></head>
      <body>
        <div class="chapter-image">
          <img src="/static/common/loading.svg"
               data-src="https://s1.toonilycdnv2.xyz/toonily/manga/abc123/chapter-1/page_1.jpg"
               alt="Page 1">
        </div>
        <div class="chapter-image">
          <img data-src="//a.exdynsrv.com/iframe.php?idzone=12345&size=300x250">
        </div>
        <div class="chapter-image">
          <img src="/static/common/loading.svg"
               data-src="https://s2.toonilycdnv2.xyz/toonily/manga/abc123/chapter-1/page_2.jpg"
               alt="Page 2">
        </div>
        <div class="chapter-image">
          <img data-src="//a.pemsrv.com/iframe.php?idzone=67890&size=300x250">
        </div>
        <div class="chapter-image">
          <img src="/static/common/loading.svg"
               data-src="https://s3.toonilycdnv2.xyz/toonily/manga/abc123/chapter-1/page_3.jpg"
               alt="Page 3">
        </div>

        <script>
          var bookId = 122;
          var bookSlug = "solo-leveling";
          var chapterId = 6375;
        </script>
      </body>
      </html>
    HTML
  end

  def browse_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Toonily AZ List</title></head>
      <body>
        <div class="grid-items">
          <div class="book-item">
            <div class="book-detailed-item">
              <div class="thumb">
                <a title="Solo Leveling" href="/solo-leveling">
                  <img class="lazy" src="/static/common/x.gif"
                       data-src="//sb.toonilycdnv2.xyz/thumb/sl-cover.png"
                       alt="Solo Leveling">
                </a>
                <span class="latest-chapter" title="Chapter 203">Chapter 203</span>
              </div>
              <div class="meta">
                <div class="title"><h3><a title="Solo Leveling" href="/solo-leveling">Solo Leveling</a></h3></div>
              </div>
            </div>
          </div>
          <div class="book-item">
            <div class="book-detailed-item">
              <div class="thumb">
                <a title="Tower of God" href="/tower-of-god">
                  <img class="lazy" src="/static/common/x.gif"
                       data-src="//sb.toonilycdnv2.xyz/thumb/tog-cover.png"
                       alt="Tower of God">
                </a>
                <span class="latest-chapter" title="Chapter 550">Chapter 550</span>
              </div>
              <div class="meta">
                <div class="title"><h3><a title="Tower of God" href="/tower-of-god">Tower of God</a></h3></div>
              </div>
            </div>
          </div>
        </div>
        <div class="paginator">
          <a href="/az-list?page=1&sort=views" class="link active">1</a>
          <a href="/az-list?page=2&sort=views" class="link">2</a>
        </div>
      </body>
      </html>
    HTML
  end
end
