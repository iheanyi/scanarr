require "test_helper"

class FileAssetTest < ActiveSupport::TestCase
  def test_public_id_is_generated
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1")
    release = Release.create!(chapter: chapter)
    asset = FileAsset.create!(release: release)

    assert asset.public_id.present?
    assert_equal 12, asset.public_id.length
    assert_equal asset.public_id, asset.to_param
  end

  def test_tracks_download_progress_fields
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1")
    release = Release.create!(chapter: chapter)
    asset = FileAsset.create!(
      release: release,
      download_status: "downloading",
      pages_expected: 10,
      pages_downloaded: 3,
      download_error: "Timeout"
    )

    assert_equal "downloading", asset.download_status
    assert_equal 10, asset.pages_expected
    assert_equal 3, asset.pages_downloaded
    assert_equal "Timeout", asset.download_error
  end
end
