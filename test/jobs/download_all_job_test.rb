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

  def test_downloads_newest_duplicate_chapter_even_when_it_has_a_lower_id
    series = series(:one)
    source = sources(:one)
    newest = series.chapters.create!(
      source: source,
      chapter_number: "99",
      source_url: "https://weebcentral.com/chapters/newest",
      created_at: 1.hour.ago
    )
    older = series.chapters.create!(
      source: source,
      chapter_number: "99",
      source_url: "https://weebcentral.com/chapters/older",
      created_at: 2.hours.ago
    )

    assert_enqueued_jobs 1, only: DownloadChapterJob do
      assert_enqueued_with(job: DownloadChapterJob, args: ->(args) { args.first == newest.source_url }) do
        DownloadAllJob.perform_now(series.id, source.id)
      end
    end

    assert_equal "queued", newest.releases.sole.file_asset.download_status
    assert_empty older.releases
  end
  test "replacement fills missing chapters with matching URLs while retaining saved files" do
    source = sources(:two)
    SeriesSource.create!(series: series(:one), source: source, source_series_id: "replacement")
    saved = chapters(:one).releases.create!(source: source, format: "pages", source_url: "https://example.com/replacement/1")
    file_assets(:two).update!(download_status: "failed")
    missing = chapters(:two).releases.create!(source: source, format: "pages", source_url: "https://example.com/replacement/2")

    DownloadAllJob.perform_now(series(:one).id, source.id)
    job = enqueued_jobs.find { |entry| entry[:job] == DownloadChapterJob && entry[:args].first == missing.source_url }

    assert_not_nil job

    arguments = ActiveJob::Arguments.deserialize(job[:args])

    assert_equal source.key, arguments.last[:source_key]
    assert_equal missing.id, arguments.last[:release_id]
    assert_equal "replacement", arguments.last[:source_series_id]
    assert_nil saved.reload.file_asset
    assert_equal "complete", file_assets(:one).reload.download_status
    assert_equal "failed", file_assets(:two).reload.download_status
    assert_equal "queued", missing.reload.file_asset.download_status
  end
end
