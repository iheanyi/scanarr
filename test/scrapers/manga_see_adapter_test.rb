require "test_helper"
require "json"
require "uri"

class MangaSeeAdapterTest < ActiveSupport::TestCase
  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(mapping:, base_url:)
      @mapping = mapping
      @base_url = base_url
    end

    def get(path_or_url, params: {}, headers: {})
      uri = URI(path_or_url.to_s)
      uri = URI.join(@base_url, path_or_url.to_s) if uri.host.nil?

      unless params.empty?
        current = URI.decode_www_form(String(uri.query))
        uri.query = URI.encode_www_form(current + params.to_a)
      end

      key = "GET #{uri}"
      fallback = uri.dup
      fallback.query = nil
      body = @mapping[key] || @mapping["GET #{fallback}"]

      return Response.new(status: 404, body: "", headers: {}, url: uri.to_s) unless body

      Response.new(status: 200, body: body, headers: {}, url: uri.to_s)
    end
  end

  def setup
    @base_url = "https://mangasee123.com"
    @slug = "Naruto"
    @chapter_code = "100100"
    @chapter_url = "#{@base_url}/read-online/#{@slug}-chapter-0001.html"

    @fixtures = {
      "GET #{@base_url}/_search.php" => search_fixture,
      "GET #{@base_url}/manga/#{@slug}" => series_fixture,
      "GET #{@chapter_url}" => pages_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::MangaSee::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  def test_search_matches_title_and_alt_title
    results = @adapter.search("naruto")

    assert_equal 2, results.size
    assert_equal "Naruto", results.first.title
    assert_equal "#{@base_url}/manga/Naruto", results.first.url
    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_series_parses_metadata
    series = @adapter.series(@slug)

    assert_equal "Naruto", series.title
    assert_equal "Masashi Kishimoto", series.author
    assert_equal "Masashi Kishimoto", series.artist
    assert_equal "completed", series.status
    assert_equal "manga", series.series_type
    assert_equal "A ninja story.", series.description
    assert_equal "https://temp.compsci88.com/cover/#{@slug}.jpg", series.cover_url
    assert_kind_of ResultTypes::Series, series
  end

  def test_chapters_decodes_numbers_and_sorts
    chapters = @adapter.chapters(@slug)

    assert_equal 2, chapters.size
    assert_equal "1", chapters.first.number
    assert_equal "2", chapters.last.number
    assert_equal @chapter_url, chapters.first.url
    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_pages_builds_image_urls
    pages = @adapter.pages(@chapter_url)

    assert_equal 2, pages.size
    assert_equal "https://cdn.mangasee123.com/manga/Naruto/0001-001.png", pages.first.url
    assert_equal "https://cdn.mangasee123.com/manga/Naruto/0001-002.png", pages.last.url
    assert_equal 0, pages.first.index
    assert_equal "image/png", pages.first.mime_type
    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_returns_empty_or_nil_on_missing_fixture
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::MangaSee::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    assert_empty adapter.search("naruto")
    assert_nil adapter.series(@slug)
    assert_empty adapter.chapters(@slug)
    assert_empty adapter.pages(@chapter_url)
  end

  private

  def search_fixture
    [
      {
        "i" => "Naruto",
        "s" => "Naruto",
        "al" => [ "NARUTO", "ナルト" ],
        "a" => [ "Masashi Kishimoto" ]
      },
      {
        "i" => "Boruto",
        "s" => "Boruto",
        "al" => [ "Naruto Next Generations" ],
        "a" => [ "Ukyo Kodachi" ]
      }
    ].to_json
  end

  def series_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="MainContainer">
          <h1>Naruto</h1>
        </div>
        <div class="list-group-item">Author: <a>Masashi Kishimoto</a></div>
        <div class="list-group-item">Artist: <a>Masashi Kishimoto</a></div>
        <div class="list-group-item">Status: <a>Completed</a></div>
        <div class="Content">A ninja story.</div>

        <script>
          vm.Chapters = [
            {"Chapter":"100200","ChapterName":"Chapter 2","Date":"2024-01-02T00:00:00Z"},
            {"Chapter":"100100","ChapterName":"Chapter 1","Date":"2024-01-01T00:00:00Z"}
          ];
        </script>
      </body>
      </html>
    HTML
  end

  def pages_fixture
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <script>
          vm.CurPathName = "cdn.mangasee123.com";
          vm.CurChapter = {"Chapter":"100100","Directory":"","Page":"2"};
        </script>
      </body>
      </html>
    HTML
  end
end
