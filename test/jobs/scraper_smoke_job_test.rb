require "test_helper"

class ScraperSmokeJobTest < ActiveJob::TestCase
  class FakeAdapter
    def search(_query)
      [
        ResultTypes::SearchResult.new(
          id: "series-123",
          title: "One Piece",
          url: "https://weebcentral.com/series/OP",
          cover_url: nil,
          language: nil
        )
      ]
    end

    def series(_url)
      ResultTypes::Series.new(id: "series-123", title: "One Piece", url: "https://weebcentral.com/series/OP")
    end

    def chapters(_series_url)
      [
        ResultTypes::Chapter.new(id: "ch-1", title: "Chapter 1", number: "1", url: "https://weebcentral.com/chapters/01CHAPTER")
      ]
    end

    def pages(_chapter_url)
      [
        ResultTypes::Page.new(index: 1, url: "https://weebcentral.com/manga/page-1.jpg", mime_type: "image/jpeg")
      ]
    end
  end

  class FailingAdapter
    def search(_query)
      raise "boom"
    end
  end

  def test_scraper_smoke_job_updates_run
    source = sources(:one)
    run = ScraperRun.create!(
      source: source,
      run_type: "smoke",
      status: "running",
      started_at: Time.current
    )

    with_adapter(FakeAdapter.new) do
      ScraperSmokeJob.perform_now(run.id)
    end

    run.reload

    assert_equal "success", run.status
    assert_predicate run.finished_at, :present?
    assert_equal 1, run.stats_json.fetch("search_count")
    assert_equal 1, run.stats_json.fetch("chapter_count")
    assert_equal 1, run.stats_json.fetch("page_count")
  end

  def test_scraper_smoke_job_records_failure
    source = sources(:one)
    run = ScraperRun.create!(
      source: source,
      run_type: "smoke",
      status: "running",
      started_at: Time.current
    )

    with_adapter(FailingAdapter.new) do
      assert_raises(RuntimeError) do
        ScraperSmokeJob.perform_now(run.id)
      end
    end

    run.reload

    assert_equal "failed", run.status
    assert_predicate run.error, :present?
    assert_predicate run.finished_at, :present?
  end

  private

  def with_adapter(adapter)
    original = ScraperSmokeJob.instance_method(:adapter_for) rescue nil
    ScraperSmokeJob.define_method(:adapter_for) { |_source| adapter }
    yield
  ensure
    if original
      ScraperSmokeJob.define_method(:adapter_for, original)
    else
      ScraperSmokeJob.remove_method(:adapter_for)
    end
  end
end
