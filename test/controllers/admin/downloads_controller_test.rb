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

  def test_cancel_queued_download_uses_public_id_route_param
    file_asset = file_assets(:one)
    file_asset.update!(download_status: "queued", download_error: nil)

    post admin_download_cancel_path(file_asset)

    assert_redirected_to admin_downloads_path
    assert_equal "Download cancelled", flash[:notice]

    file_asset.reload

    assert_equal "cancelled", file_asset.download_status
  end

  def test_restart_failed_download_uses_public_id_route_param
    file_asset = file_assets(:one)
    file_asset.update!(download_status: "failed", download_error: "network error")

    post admin_download_restart_path(file_asset)

    assert_redirected_to admin_downloads_path
    assert_equal "Download restarted successfully", flash[:notice]

    file_asset.reload

    assert_equal "queued", file_asset.download_status
    assert_nil file_asset.download_error
  end
end
