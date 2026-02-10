require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  class FakeSearchAdapter
    def initialize(results:)
      @results = results
    end

    def search(_query)
      @results
    end
  end

  def test_index_returns_success
    get search_path

    assert_response :success
  end

  def test_index_shows_source_checkboxes
    get search_path

    assert_response :success
    assert_includes @response.body, 'type="checkbox"'
    assert_includes @response.body, "sources[]"
  end

  def test_index_shows_search_form
    get search_path

    assert_response :success
    assert_includes @response.body, 'name="q"'
    assert_includes @response.body, "Search"
  end

  def test_index_hides_mature_sources_by_default
    get search_path

    assert_response :success
    assert_includes @response.body, "Show 18+ sources"
    assert_includes @response.body, "18+ sources hidden"
    assert_not_includes @response.body, "Manhwa18 (18+)"
    assert_not_includes @response.body, %(value="#{sources(:mature).id}")
  end

  def test_index_can_include_mature_sources_with_toggle
    get search_path, params: { include_mature: "1" }

    assert_response :success
    assert_includes @response.body, "Show 18+ sources"
    assert_includes @response.body, "Manhwa18 (18+)"
    assert_includes @response.body, %(value="#{sources(:mature).id}")
  end

  def test_index_renders_sidebar_navigation
    get search_path

    assert_response :success
    assert_includes @response.body, 'data-sidebar-nav="true"'
    assert_includes @response.body, 'data-controller="drawer"'
    assert_includes @response.body, "<dialog"
    assert_includes @response.body, 'aria-current="page"'
    assert_includes @response.body, 'data-action="click-&gt;drawer#close"'
    assert_includes @response.body, ">Browse<"
  end

  def test_index_without_query_shows_no_results
    get search_path

    assert_response :success
    assert_no_match /Results/, @response.body
  end

  def test_index_shows_advanced_filter_controls
    get search_path

    assert_response :success
    assert_includes @response.body, "Advanced filters"
    assert_includes @response.body, "Genres"
    assert_includes @response.body, 'name="status"'
  end

  def test_index_filters_results_by_genre_for_imported_series
    source = sources(:one)
    series(:one).update!(normalized_categories: [ "action", "adventure" ])
    adapter = FakeSearchAdapter.new(results: [ search_result(id: "SERIES123", title: "One Piece"), search_result(id: "NOT_MATCHED", title: "Other Title") ])

    with_fake_adapter(adapter) do
      get search_path, params: { q: "piece", sources: [ source.id ], genres: [ "action" ] }

      assert_response :success
      assert_includes @response.body, "One Piece"
      assert_not_includes @response.body, "Other Title"
    end
  end

  def test_index_filters_results_by_following_status
    source = sources(:one)
    adapter = FakeSearchAdapter.new(results: [ search_result(id: "SERIES123", title: "One Piece"), search_result(id: "NOT_MATCHED", title: "Other Title") ])

    with_fake_adapter(adapter) do
      get search_path, params: { q: "piece", sources: [ source.id ], status: "following" }

      assert_response :success
      assert_includes @response.body, "One Piece"
      assert_not_includes @response.body, "Other Title"
      assert_includes @response.body, "Status: Following"
    end
  end

  private

  def search_result(id:, title:)
    ResultTypes::SearchResult.new(
      id: id,
      title: title,
      url: "https://example.test/series/#{id}",
      cover_url: "https://example.test/cover/#{id}.jpg"
    )
  end

  def with_fake_adapter(adapter)
    original_for = Scrapers::AdapterRegistry.method(:for)
    Scrapers::AdapterRegistry.define_singleton_method(:for) { |_source| adapter }
    yield
  ensure
    Scrapers::AdapterRegistry.define_singleton_method(:for, original_for)
  end
end
