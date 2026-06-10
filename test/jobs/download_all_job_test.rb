require "test_helper"

class DownloadAllJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  def test_retries_failed_downloads_as_queued_before_enqueueing_chapter_jobs
    series = series(:one)
    source = sources(:one)
    chapter = chapters(:two)
    release = releases(:two)
    file_asset = file_assets(:two)
    file_asset.update!(
      download_status: "failed",
      pages_downloaded: 1,
      pages_expected: 3,
      download_error: "RuntimeError: Timeout",
      path: "library/old-layout"
    )

    assert_enqueued_with(job: DownloadChapterJob) do
      DownloadAllJob.perform_now(series.id, source.id)
    end

    file_asset.reload

    assert_equal "queued", file_asset.download_status
    assert_equal 0, file_asset.pages_downloaded
    assert_nil file_asset.pages_expected
    assert_nil file_asset.download_error
    assert_equal "library/weeb-central/one-piece--#{series.public_id}/chapters/2--#{chapter.public_id}", file_asset.path
  end
end
