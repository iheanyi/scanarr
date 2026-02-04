require "test_helper"

class LayoutNavTest < ActionDispatch::IntegrationTest
  def test_layout_includes_design_system_link
    get "/"

    assert_response :success
    assert_includes @response.body, "Design System"
    assert_includes @response.body, "/design-system"
  end
end
