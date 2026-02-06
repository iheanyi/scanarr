require "test_helper"

class ImportSeriesJobTest < ActiveJob::TestCase
  class FakeAdapter
    def series(_url)
      ResultTypes::Series.new(
        id: "series-123",
        title: "One Piece",
        url: "https://weebcentral.com/series/OP",
        tags: [ "Action" ],
        status: "ongoing",
        series_type: "manga"
      )
    end

    def chapters(_series_url)
      [
        ResultTypes::Chapter.new(id: "ch-1", title: "Chapter 1", number: "1", url: "https://weebcentral.com/chapters/01CHAPTER"),
        ResultTypes::Chapter.new(id: "ch-2", title: "Chapter 2", number: "2", url: "https://weebcentral.com/chapters/02CHAPTER")
      ]
    end
  end

  class FailingAdapter
    def series(_url)
      raise "boom"
    end

    def chapters(_series_url)
      []
    end
  end

  def test_import_series_job_updates_scraper_run
    source = sources(:one)
    run = ScraperRun.create!(
      source: source,
      run_type: "import",
      status: "running",
      started_at: Time.current
    )

    with_adapter(FakeAdapter.new) do
      ImportSeriesJob.perform_now(run.id, "https://weebcentral.com/series/OP")
    end

    run.reload

    assert_equal "success", run.status
    assert_predicate run.finished_at, :present?
    assert_equal "https://weebcentral.com/series/OP", run.stats_json.fetch("series_url")
    assert_equal 2, run.stats_json.fetch("chapter_count")
  end

  def test_import_series_job_records_failure
    source = sources(:one)
    run = ScraperRun.create!(
      source: source,
      run_type: "import",
      status: "running",
      started_at: Time.current
    )

    with_adapter(FailingAdapter.new) do
      assert_raises(RuntimeError) do
        ImportSeriesJob.perform_now(run.id, "https://weebcentral.com/series/OP")
      end
    end

    run.reload

    assert_equal "failed", run.status
    assert_predicate run.error, :present?
    assert_predicate run.finished_at, :present?
  end

  private

  def with_adapter(adapter)
    original = ImportSeriesJob.instance_method(:adapter_for) rescue nil
    ImportSeriesJob.define_method(:adapter_for) { |_source| adapter }
    yield
  ensure
    if original
      ImportSeriesJob.define_method(:adapter_for, original)
    else
      ImportSeriesJob.remove_method(:adapter_for)
    end
  end
end
