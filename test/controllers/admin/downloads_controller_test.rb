require "test_helper"

class Admin::DownloadsControllerTest < ActionDispatch::IntegrationTest
  def test_index_sorts_by_status_priority_and_downloading_progress
    downloading_low = file_assets(:one)
    downloading_low.update!(
      download_status: "downloading",
      pages_expected: 10,
      pages_downloaded: 2,
      updated_at: 2.minutes.ago
    )

    downloading_high = file_assets(:two)
    downloading_high.update!(
      download_status: "downloading",
      pages_expected: 10,
      pages_downloaded: 8,
      updated_at: 6.minutes.ago
    )

    queued = file_assets(:three)
    queued.update!(
      download_status: "queued",
      pages_expected: nil,
      pages_downloaded: 0,
      updated_at: 1.minute.ago
    )

    complete = FileAsset.create!(
      release: releases(:one),
      public_id: "sortcomplete001",
      format: "pages",
      download_status: "complete",
      pages_expected: 10,
      pages_downloaded: 10,
      updated_at: 30.seconds.ago
    )

    failed = FileAsset.create!(
      release: releases(:two),
      public_id: "sortfailed001",
      format: "pages",
      download_status: "failed",
      pages_expected: 10,
      pages_downloaded: 1,
      updated_at: Time.current
    )

    get admin_downloads_path

    assert_response :success

    body = @response.body
    order = [
      row_index(body, downloading_high),
      row_index(body, downloading_low),
      row_index(body, queued),
      row_index(body, complete),
      row_index(body, failed)
    ]

    order.each do |idx|
      assert_not_nil idx
    end

    assert_operator order[0], :<, order[1]
    assert_operator order[1], :<, order[2]
    assert_operator order[2], :<, order[3]
    assert_operator order[3], :<, order[4]
  end

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

  def test_index_hides_restart_button_for_downloading_rows
    file_asset = file_assets(:one)
    file_asset.update!(
      download_status: "downloading",
      pages_expected: 10,
      pages_downloaded: 3,
      updated_at: Time.current
    )

    get admin_downloads_path

    assert_response :success

    row_html = row_html(@response.body, file_asset)

    assert_not_nil row_html
    assert_no_match />Restart</, row_html
    assert_match />\s*Cancel\s*<\/button>/m, row_html
  end

  private

  def row_index(body, file_asset)
    body.index("id=\"file_asset_#{file_asset.id}\"")
  end

  def row_html(body, file_asset)
    body.match(%r{<tr id="file_asset_#{file_asset.id}".*?</tr>}m)&.to_s
  end
end
