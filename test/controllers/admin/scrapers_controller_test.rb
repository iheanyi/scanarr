require "test_helper"

class Admin::ScrapersControllerTest < ActionDispatch::IntegrationTest
  def test_index_returns_success
    get admin_scrapers_path
    assert_response :success
  end

  def test_index_filters_by_status
    get admin_scrapers_path(status: "success")
    assert_response :success
    # Status badge renders within a span; "failed" appears in the filter dropdown
    # but should not appear as a status badge in the table body
    assert_match /bg-success-soft text-success/, @response.body
    assert_no_match /bg-danger-soft text-danger/, @response.body
  end
end
