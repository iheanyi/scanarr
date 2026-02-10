require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  class FakeAdapter
    def search(_query)
      [
        ResultTypes::SearchResult.new(
          id: "series-123",
          title: "One Piece",
          url: "https://weebcentral.com/series/OP",
          cover_url: "https://img.example.com/cover.jpg",
          language: nil
        )
      ]
    end

    def series(_url)
      ResultTypes::Series.new(id: "series-123", title: "One Piece", url: "https://weebcentral.com/series/OP")
    end

    def chapters(_series_url)
      [
        ResultTypes::Chapter.new(id: "ch-1", title: "Chapter 1", number: "1", url: "https://weebcentral.com/chapters/01CHAPTER")
      ]
    end
  end

  def test_index_returns_success
    get "/"

    assert_response :success
    assert_includes @response.body, "Weeb Central"
    assert_includes @response.body, "/sources/weeb-central"
    assert_includes @response.body, "application-" # CSS asset
  end

  def test_index_navigation_buttons_escape_turbo_frame
    get "/"

    assert_response :success
    assert_select %(turbo-frame#sources-content a[data-turbo-frame="_top"]), minimum: 3
  end

  def test_sources_turbo_frame_links_always_declare_navigation_target
    get "/"

    assert_response :success
    assert_select "turbo-frame#sources-content a[href]:not([href^='#']):not([data-turbo-frame])", 0
  end

  def test_search_shows_results
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/search", params: { q: "one piece" }

      assert_response :success
      assert_includes @response.body, "One Piece"
      assert_includes @response.body, "https://img.example.com/cover.jpg"
    end
  end

  def test_import_creates_series
    with_adapter(FakeAdapter.new) do
      post "/sources/weeb-central/import", params: { series_url: "https://weebcentral.com/series/OP" }
      # Find the newly created series to get its public_id-slug format
      series = Series.find_by(canonical_title: "One Piece")

      assert_redirected_to library_series_path(series_slug: series.to_param)
    end
  end

  private

  def with_adapter(adapter)
    # Stub Scrapers::AdapterRegistry.for to return fake adapter
    original_for = Scrapers::AdapterRegistry.method(:for)
    Scrapers::AdapterRegistry.define_singleton_method(:for) { |_source| adapter }
    yield
  ensure
    Scrapers::AdapterRegistry.define_singleton_method(:for, original_for)
  end
end
