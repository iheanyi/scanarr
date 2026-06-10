require "test_helper"

class CleanupOrphanedDownloadsJobTest < ActiveJob::TestCase
  setup do
    pages(:one).image.attach(io: StringIO.new("page-1"), filename: "001.jpg", content_type: "image/jpeg")
  end

  test "marks completed downloads with missing blobs as recoverable failures" do
    file_asset = file_assets(:one)
    file_asset.update!(download_status: "complete", download_error: nil)
    first_page = file_asset.pages.order(:position).first
    blob = first_page.image.blob

    ActiveStorage::Blob.service.delete(blob.key)

    CleanupOrphanedDownloadsJob.perform_now

    file_asset.reload

    assert_equal "failed", file_asset.download_status
    assert_equal "Orphaned: blob files missing from storage (detected by cleanup job)", file_asset.download_error
  end

  test "leaves completed downloads alone when blobs exist" do
    file_asset = file_assets(:one)
    file_asset.update!(download_status: "complete", download_error: nil)

    CleanupOrphanedDownloadsJob.perform_now

    file_asset.reload

    assert_equal "complete", file_asset.download_status
    assert_nil file_asset.download_error
  end
end
