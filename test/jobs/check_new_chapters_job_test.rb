# frozen_string_literal: true

require "test_helper"

class CheckNewChaptersJobTest < ActiveJob::TestCase
  setup do
    @series = series(:one)
    @source = sources(:one)
    @series_source = series_sources(:one)
    @follow = user_series_follows(:one)
  end

  test "enqueues CheckSourceForChaptersJob for each series_source with source_series_id" do
    assert_enqueued_with(
      job: CheckSourceForChaptersJob,
      args: [ @series.id, @follow.id, @source.id ]
    ) do
      CheckNewChaptersJob.perform_now
    end
  end

  test "skips series_sources without source_series_id" do
    @series_source.update!(source_series_id: nil)

    assert_no_enqueued_jobs(only: CheckSourceForChaptersJob) do
      CheckNewChaptersJob.perform_now
    end
  end

  test "handles follows with no series gracefully" do
    @series.series_sources.destroy_all

    assert_nothing_raised do
      CheckNewChaptersJob.perform_now
    end
  end
end
