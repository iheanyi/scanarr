require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
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
end
