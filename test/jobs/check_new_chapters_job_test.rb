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

  # --- Phase 3: Smart Scheduling ---

  test "skips series_source checked recently when follow has custom interval" do
    @follow.update!(check_interval_minutes: 60)
    @series_source.update!(last_checked_at: 30.minutes.ago)

    assert_no_enqueued_jobs(only: CheckSourceForChaptersJob) do
      CheckNewChaptersJob.perform_now
    end
  end

  test "enqueues job when series_source was checked beyond follow interval" do
    @follow.update!(check_interval_minutes: 60)
    @series_source.update!(last_checked_at: 61.minutes.ago)

    assert_enqueued_with(
      job: CheckSourceForChaptersJob,
      args: [ @series.id, @follow.id, @source.id ]
    ) do
      CheckNewChaptersJob.perform_now
    end
  end

  test "enqueues job when series_source was never checked" do
    @series_source.update!(last_checked_at: nil)

    assert_enqueued_with(
      job: CheckSourceForChaptersJob,
      args: [ @series.id, @follow.id, @source.id ]
    ) do
      CheckNewChaptersJob.perform_now
    end
  end

  test "skips rate-limited sources" do
    @source.update!(rate_limited_until: 5.minutes.from_now)

    assert_no_enqueued_jobs(only: CheckSourceForChaptersJob) do
      CheckNewChaptersJob.perform_now
    end
  end

  test "does not skip source with expired rate limit" do
    @source.update!(rate_limited_until: 1.minute.ago)

    assert_enqueued_with(
      job: CheckSourceForChaptersJob,
      args: [ @series.id, @follow.id, @source.id ]
    ) do
      CheckNewChaptersJob.perform_now
    end
  end

  test "uses default interval when follow has no custom interval" do
    @follow.update!(check_interval_minutes: nil)
    @series_source.update!(last_checked_at: 31.minutes.ago)

    assert_enqueued_with(
      job: CheckSourceForChaptersJob,
      args: [ @series.id, @follow.id, @source.id ]
    ) do
      CheckNewChaptersJob.perform_now
    end
  end

  test "default interval skips recently checked sources" do
    @follow.update!(check_interval_minutes: nil)
    @series_source.update!(last_checked_at: 10.minutes.ago)

    assert_no_enqueued_jobs(only: CheckSourceForChaptersJob) do
      CheckNewChaptersJob.perform_now
    end
  end
end
