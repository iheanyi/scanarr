require "test_helper"

class DesignSystemControllerTest < ActionDispatch::IntegrationTest
  def test_show_renders_sections
    get design_system_path

    assert_response :success
    assert_includes @response.body, "Design System"
    assert_includes @response.body, "id=\"overview\""
    assert_includes @response.body, "id=\"tokens\""
    assert_includes @response.body, "id=\"components\""
    assert_includes @response.body, "id=\"guidelines\""
    assert_includes @response.body, "id=\"roadmap\""
  end
end
