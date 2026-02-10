require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  def test_serves_manifest
    get pwa_manifest_path

    assert_response :success
    assert_equal "application/manifest+json", @response.media_type
    assert_includes @response.body, "\"display\": \"standalone\""
    assert_includes @response.body, "\"start_url\": \"/library\""
  end

  def test_serves_service_worker
    get pwa_service_worker_path

    assert_response :success
    assert_equal "application/javascript", @response.media_type
    assert_includes @response.body, "PREFETCH_CHAPTER"
    assert_equal "/", @response.headers["Service-Worker-Allowed"]
  end

  def test_offline_page_renders
    get pwa_offline_path

    assert_response :success
    assert_includes @response.body, "You are offline"
  end
end
