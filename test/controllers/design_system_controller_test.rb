require "test_helper"

class DesignSystemControllerTest < ActionDispatch::IntegrationTest
  def test_show_renders_sections
    get design_system_path

    assert_response :success
    assert_includes @response.body, "Panel Pulse"
    assert_includes @response.body, "id=\"panel-pulse\""
    assert_includes @response.body, "id=\"ink-noir\""
    assert_includes @response.body, "id=\"editorial-shelf\""
  end
end
