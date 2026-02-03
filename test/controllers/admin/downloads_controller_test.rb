require "test_helper"

class Admin::DownloadsControllerTest < ActionDispatch::IntegrationTest
  def test_index_returns_success
    get admin_downloads_path
    assert_response :success
  end

  def test_index_shows_stats_cards
    get admin_downloads_path
    assert_response :success
    assert_includes @response.body, "Queued"
    assert_includes @response.body, "Downloading"
    assert_includes @response.body, "Complete"
    assert_includes @response.body, "Failed"
  end

  def test_index_filters_by_status
    # Create a completed download
    file_asset = file_assets(:one)
    file_asset.update!(download_status: "complete")

    get admin_downloads_path(status: "complete")
    assert_response :success
    assert_match />complete</, @response.body.downcase
  end
end
