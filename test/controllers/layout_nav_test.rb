require "test_helper"

class LayoutNavTest < ActionDispatch::IntegrationTest
  def test_navigation_groups_tools_and_marks_library_home_active
    get root_path

    assert_response :success
    assert_select "nav[data-sidebar-nav]" do
      assert_select "a[href='/library'][aria-current=page]", text: "Library"
      assert_select "a[href='/sources']", text: "Browse sources"
      assert_select "details summary", text: "Library tools"
      assert_select "details summary", text: "Server management"
    end
    assert_select "[data-notification-count]", count: 2
    assert_select "#notification-count", count: 0
  end

  def test_layout_includes_design_system_link
    get "/"

    assert_response :success
    assert_includes @response.body, "Design System"
    assert_includes @response.body, "/design-system"
  end
end
