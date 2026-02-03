require "test_helper"

class Admin::ScrapersControllerTest < ActionDispatch::IntegrationTest
  def test_index_returns_success
    get admin_scrapers_path
    assert_response :success
  end

  def test_index_filters_by_status
    get admin_scrapers_path(status: "success")
    assert_response :success
    # Table cells have Tailwind classes, so check for status text within td
    assert_match />success<\/td>/, @response.body
    assert_no_match />failed<\/td>/, @response.body
  end
end
