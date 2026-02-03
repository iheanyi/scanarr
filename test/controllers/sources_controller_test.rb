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
      assert_redirected_to "/sources/weeb-central/#{series.to_param}"
    end
  end

  private

  def with_adapter(adapter)
    original = SourcesController.instance_method(:adapter_for) rescue nil
    SourcesController.define_method(:adapter_for) { |_source = nil| adapter }
    yield
  ensure
    if original
      SourcesController.define_method(:adapter_for, original)
    else
      SourcesController.remove_method(:adapter_for)
    end
  end
end
