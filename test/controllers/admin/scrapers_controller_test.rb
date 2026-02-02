require "test_helper"

class Admin::ScrapersControllerTest < ActionDispatch::IntegrationTest
  def test_index_returns_success
    get admin_scrapers_path
    assert_response :success
  end

  def test_index_filters_by_status
    get admin_scrapers_path(status: "success")
    assert_response :success
    assert_includes @response.body, "<td>success</td>"
    assert_not_includes @response.body, "<td>failed</td>"
  end
end
