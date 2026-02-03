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

  def test_index_without_query_shows_no_results
    get search_path
    assert_response :success
    assert_no_match /Results/, @response.body
  end
end
