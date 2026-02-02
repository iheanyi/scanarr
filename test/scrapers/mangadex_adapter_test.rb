require "test_helper"
require "json"
require "uri"

class MangadexAdapterTest < ActiveSupport::TestCase
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
      body = @mapping[key] || @mapping.fetch("GET #{fallback}")
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
    @base_url = "https://api.mangadex.org"
    @manga_id = "123e4567-e89b-12d3-a456-426614174000"
    @chapter_id = "123e4567-e89b-12d3-a456-426614174111"
    @fixtures = {
      "GET #{@base_url}/manga" => search_fixture,
      "GET #{@base_url}/manga/#{@manga_id}" => manga_fixture,
      "GET #{@base_url}/chapter" => chapter_fixture,
      "GET #{@base_url}/at-home/server/#{@chapter_id}" => pages_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Mangadex::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  def test_search_returns_results
    results = @adapter.search("naruto")
    assert_equal 1, results.size
    assert_equal "Naruto", results.first.title
  end

  def test_series_parses_tags_and_type
    series = @adapter.series(@manga_id)
    assert_equal "Naruto", series.title
    assert_includes series.tags, "Action"
    assert_equal "manga", series.series_type
  end

  def test_chapters_returns_list
    chapters = @adapter.chapters(@manga_id)
    assert_equal 2, chapters.size
    assert_equal "1", chapters.first.number
  end

  def test_pages_returns_urls
    pages = @adapter.pages(@chapter_id)
    assert_equal 2, pages.size
    assert_match %r{/data/}, pages.first.url
  end

  private

  def search_fixture
    {
      "data" => [
        {
          "id" => @manga_id,
          "attributes" => {
            "title" => { "en" => "Naruto" },
            "originalLanguage" => "ja"
          },
          "relationships" => [
            { "type" => "cover_art", "attributes" => { "fileName" => "cover.jpg" } }
          ]
        }
      ]
    }.to_json
  end

  def manga_fixture
    {
      "data" => {
        "id" => @manga_id,
        "attributes" => {
          "title" => { "en" => "Naruto" },
          "description" => { "en" => "A ninja story." },
          "originalLanguage" => "ja",
          "status" => "ongoing",
          "tags" => [
            { "attributes" => { "name" => { "en" => "Action" } } },
            { "attributes" => { "name" => { "en" => "Shonen" } } }
          ]
        },
        "relationships" => [
          { "type" => "cover_art", "attributes" => { "fileName" => "cover.jpg" } }
        ]
      }
    }.to_json
  end

  def chapter_fixture
    {
      "total" => 2,
      "data" => [
        {
          "id" => @chapter_id,
          "attributes" => {
            "title" => "Chapter 1",
            "chapter" => "1",
            "volume" => "1",
            "translatedLanguage" => "en",
            "publishAt" => "2024-01-01T00:00:00Z"
          }
        },
        {
          "id" => "123e4567-e89b-12d3-a456-426614174222",
          "attributes" => {
            "title" => "Chapter 2",
            "chapter" => "2",
            "volume" => "1",
            "translatedLanguage" => "en",
            "publishAt" => "2024-01-02T00:00:00Z"
          }
        }
      ]
    }.to_json
  end

  def pages_fixture
    {
      "baseUrl" => "https://uploads.mangadex.org",
      "chapter" => {
        "hash" => "abcdef",
        "data" => [ "001.jpg", "002.jpg" ]
      }
    }.to_json
  end
end
