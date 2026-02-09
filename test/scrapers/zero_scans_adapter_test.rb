require "test_helper"
require "json"
require "uri"

class ZeroScansAdapterTest < ActiveSupport::TestCase
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
    @base_url = "https://zscans.com"
    @series_slug = "solo-leveling"
    @series_id = 42
    @chapter_id = 1001
    @fixtures = {
      "GET #{@base_url}/swordflake/comics" => comics_fixture,
      "GET #{@base_url}/swordflake/comic/#{@series_id}/chapters" => chapters_fixture,
      "GET #{@base_url}/swordflake/comic/#{@series_slug}/chapters/#{@chapter_id}" => pages_fixture
    }
    @http = FakeHttpClient.new(mapping: @fixtures, base_url: @base_url)
    @adapter = Scrapers::ZeroScans::Adapter.new(config: { "base_url" => @base_url }, http: @http)
  end

  # --- Search Tests ---

  def test_search_returns_results
    results = @adapter.search("solo")

    assert_equal 1, results.size
    assert_equal "Solo Leveling", results.first.title
    assert_equal @series_slug, results.first.id
  end

  def test_search_returns_search_result_structs
    results = @adapter.search("solo")

    assert_kind_of ResultTypes::SearchResult, results.first
  end

  def test_search_includes_cover_url
    results = @adapter.search("solo")

    assert_not_nil results.first.cover_url
    assert_match %r{https://}, results.first.cover_url
  end

  def test_search_filters_by_name
    results = @adapter.search("nonexistent manga xyz")

    assert_equal [], results
  end

  def test_search_is_case_insensitive
    results = @adapter.search("SOLO LEVELING")

    assert_equal 1, results.size
    assert_equal "Solo Leveling", results.first.title
  end

  def test_search_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::ZeroScans::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    results = adapter.search("solo")

    assert_equal [], results
  end

  def test_search_builds_url_with_id
    results = @adapter.search("solo")

    assert_equal "#{@base_url}/comics/#{@series_slug}?id=#{@series_id}", results.first.url
  end

  # --- Series Tests ---

  def test_series_parses_details
    series = @adapter.series("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    assert_equal "Solo Leveling", series.title
    assert_equal "ongoing", series.status
    assert_includes series.tags, "Action"
    assert_includes series.tags, "Fantasy"
  end

  def test_series_returns_series_struct
    series = @adapter.series("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    assert_kind_of ResultTypes::Series, series
  end

  def test_series_extracts_cover
    series = @adapter.series("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    assert_not_nil series.cover_url
    assert_match %r{https://}, series.cover_url
  end

  def test_series_extracts_description
    series = @adapter.series("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    assert_not_nil series.description
    assert_includes series.description, "weakest hunter"
  end

  def test_series_from_slug
    series = @adapter.series(@series_slug)

    assert_equal "Solo Leveling", series.title
  end

  def test_series_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::ZeroScans::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.series("#{@base_url}/comics/nonexistent")

    assert_nil result
  end

  def test_series_not_found_returns_nil
    result = @adapter.series("nonexistent-slug-xyz")

    assert_nil result
  end

  # --- Chapters Tests ---

  def test_chapters_returns_list
    chapters = @adapter.chapters("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    assert_equal 3, chapters.size
  end

  def test_chapters_returns_chapter_structs
    chapters = @adapter.chapters("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    assert_kind_of ResultTypes::Chapter, chapters.first
  end

  def test_chapters_extracts_numbers
    chapters = @adapter.chapters("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    numbers = chapters.map(&:number).map(&:to_f)
    assert_includes numbers, 1.0
    assert_includes numbers, 2.0
    assert_includes numbers, 3.0
  end

  def test_chapters_sorted_by_number
    chapters = @adapter.chapters("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    numbers = chapters.map { |ch| ch.number.to_f }
    assert_equal numbers.sort, numbers
  end

  def test_chapters_builds_urls
    chapters = @adapter.chapters("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    chapters.each do |chapter|
      assert chapter.url.start_with?("#{@base_url}/comics/#{@series_slug}/")
    end
  end

  def test_chapters_extracts_group
    chapters = @adapter.chapters("#{@base_url}/comics/#{@series_slug}?id=#{@series_id}")

    chapter_with_group = chapters.find { |ch| ch.group.present? }
    assert_not_nil chapter_with_group
    assert_equal "Zero Scans", chapter_with_group.group
  end

  def test_chapters_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::ZeroScans::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.chapters("#{@base_url}/comics/nonexistent?id=99999")

    assert_equal [], result
  end

  # --- Pages Tests ---

  def test_pages_returns_urls
    pages = @adapter.pages("#{@base_url}/comics/#{@series_slug}/#{@chapter_id}")

    assert_equal 3, pages.size
  end

  def test_pages_returns_page_structs
    pages = @adapter.pages("#{@base_url}/comics/#{@series_slug}/#{@chapter_id}")

    assert_kind_of ResultTypes::Page, pages.first
  end

  def test_pages_extracts_image_urls
    pages = @adapter.pages("#{@base_url}/comics/#{@series_slug}/#{@chapter_id}")

    pages.each do |page|
      assert page.url.start_with?("https://")
      assert page.url.match?(/\.(jpg|jpeg|png|webp)/i)
    end
  end

  def test_pages_prefers_high_quality
    pages = @adapter.pages("#{@base_url}/comics/#{@series_slug}/#{@chapter_id}")

    # Our fixture has high_quality URLs with "high" in them
    assert pages.first.url.include?("high"), "Should prefer high quality images"
  end

  def test_pages_falls_back_to_good_quality
    good_quality_fixture = {
      "GET #{@base_url}/swordflake/comics" => comics_fixture,
      "GET #{@base_url}/swordflake/comic/#{@series_slug}/chapters/#{@chapter_id}" => pages_fixture_good_quality_only
    }
    http = FakeHttpClient.new(mapping: good_quality_fixture, base_url: @base_url)
    adapter = Scrapers::ZeroScans::Adapter.new(config: { "base_url" => @base_url }, http: http)

    pages = adapter.pages("#{@base_url}/comics/#{@series_slug}/#{@chapter_id}")

    assert_equal 3, pages.size
    assert pages.first.url.include?("good"), "Should fall back to good quality"
  end

  def test_pages_handles_error_gracefully
    error_http = FakeHttpClient.new(mapping: {}, base_url: @base_url)
    adapter = Scrapers::ZeroScans::Adapter.new(config: { "base_url" => @base_url }, http: error_http)

    result = adapter.pages("#{@base_url}/comics/solo-leveling/99999")

    assert_equal [], result
  end

  def test_pages_includes_mime_type
    pages = @adapter.pages("#{@base_url}/comics/#{@series_slug}/#{@chapter_id}")

    pages.each do |page|
      assert_not_nil page.mime_type
      assert_match %r{image/}, page.mime_type
    end
  end

  # --- Browse Tests ---

  def test_supports_browse
    assert @adapter.supports_browse?
  end

  def test_browse_returns_browse_results
    results = @adapter.browse(sort: "latest", page: 1)

    assert results.size > 0
    assert_kind_of ResultTypes::BrowseResult, results.first
  end

  def test_browse_popular_sorts_by_views
    results = @adapter.browse(sort: "popular", page: 1)

    assert results.size > 0
    # The most viewed should come first
    assert_equal "One Piece", results.first.title
  end

  def test_browse_alphabetical
    results = @adapter.browse(sort: "alphabetical", page: 1)

    assert results.size > 0
    titles = results.map(&:title)
    assert_equal titles.sort_by(&:downcase), titles
  end

  def test_browse_includes_chapter_count
    results = @adapter.browse(sort: "latest", page: 1)

    result_with_chapters = results.find { |r| r.chapter_count.present? }
    assert_not_nil result_with_chapters
    assert result_with_chapters.chapter_count > 0
  end

  def test_browse_includes_status
    results = @adapter.browse(sort: "latest", page: 1)

    result_with_status = results.find { |r| r.status.present? }
    assert_not_nil result_with_status
    assert_includes %w[ongoing completed hiatus cancelled], result_with_status.status
  end

  private

  def comics_fixture
    {
      success: true,
      data: {
        comics: [
          {
            name: "Solo Leveling",
            slug: "solo-leveling",
            id: 42,
            cover: {
              full: "https://cdn.zscans.com/covers/solo-leveling-full.jpg",
              horizontal: "https://cdn.zscans.com/covers/solo-leveling-horizontal.jpg",
              vertical: "https://cdn.zscans.com/covers/solo-leveling-vertical.jpg"
            },
            summary: "The weakest hunter of all mankind, Sung Jin-Woo.",
            statuses: [ { name: "Ongoing", id: 5 } ],
            genres: [ { name: "Action", id: 1 }, { name: "Fantasy", id: 2 } ],
            chapter_count: 180,
            bookmark_count: 5000,
            view_count: 100000,
            rating: 4.8
          },
          {
            name: "One Piece",
            slug: "one-piece",
            id: 43,
            cover: {
              full: "https://cdn.zscans.com/covers/one-piece-full.jpg",
              horizontal: nil,
              vertical: nil
            },
            summary: "A boy who wants to become the Pirate King.",
            statuses: [ { name: "Ongoing", id: 5 } ],
            genres: [ { name: "Action", id: 1 }, { name: "Adventure", id: 3 } ],
            chapter_count: 1100,
            bookmark_count: 8000,
            view_count: 500000,
            rating: 4.9
          }
        ],
        genres: [
          { name: "Action", id: 1 },
          { name: "Fantasy", id: 2 },
          { name: "Adventure", id: 3 }
        ],
        statuses: [
          { name: "New", id: 1 },
          { name: "Ongoing", id: 5 },
          { name: "Completed", id: 3 },
          { name: "Dropped", id: 4 }
        ],
        rankings: {
          all_time: [ { slug: "one-piece" }, { slug: "solo-leveling" } ],
          weekly_comics: [ { slug: "solo-leveling" } ],
          monthly_comics: [ { slug: "one-piece" } ]
        }
      }
    }.to_json
  end

  def chapters_fixture
    {
      success: true,
      data: {
        data: [
          { id: 1003, name: 3, group: "Zero Scans", created_at: "2 days ago" },
          { id: 1002, name: 2, group: "Zero Scans", created_at: "5 days ago" },
          { id: 1001, name: 1, group: "Zero Scans", created_at: "1 week ago" }
        ],
        current_page: 1,
        last_page: 1
      }
    }.to_json
  end

  def pages_fixture
    {
      success: true,
      data: {
        chapter: {
          high_quality: [
            "https://cdn.zscans.com/pages/solo-leveling/1/high-001.jpg",
            "https://cdn.zscans.com/pages/solo-leveling/1/high-002.jpg",
            "https://cdn.zscans.com/pages/solo-leveling/1/high-003.jpg"
          ],
          good_quality: [
            "https://cdn.zscans.com/pages/solo-leveling/1/good-001.jpg",
            "https://cdn.zscans.com/pages/solo-leveling/1/good-002.jpg",
            "https://cdn.zscans.com/pages/solo-leveling/1/good-003.jpg"
          ]
        }
      }
    }.to_json
  end

  def pages_fixture_good_quality_only
    {
      success: true,
      data: {
        chapter: {
          high_quality: [],
          good_quality: [
            "https://cdn.zscans.com/pages/solo-leveling/1/good-001.jpg",
            "https://cdn.zscans.com/pages/solo-leveling/1/good-002.jpg",
            "https://cdn.zscans.com/pages/solo-leveling/1/good-003.jpg"
          ]
        }
      }
    }.to_json
  end
end
