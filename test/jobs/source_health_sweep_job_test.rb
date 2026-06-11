require "test_helper"

class SourceHealthSweepJobTest < ActiveSupport::TestCase
  setup do
    @job = SourceHealthSweepJob.new
    @source = Source.create!(
      key: "sweep_probe",
      name: "Sweep Probe",
      base_url: "https://example.test",
      health_status: "broken",
      health_changed_at: 1.day.ago
    )
  end

  test "recheck backs off based on how long the source has been broken" do
    @source.update!(health_changed_at: 1.day.ago)

    assert_equal 6.hours, @job.send(:recheck_interval, @source)

    @source.update!(health_changed_at: 10.days.ago)

    assert_equal 24.hours, @job.send(:recheck_interval, @source)

    @source.update!(health_changed_at: 30.days.ago)

    assert_equal 7.days, @job.send(:recheck_interval, @source)
  end

  test "recheck is due with no prior runs and not due right after one" do
    assert @job.send(:recheck_due?, @source)

    ScraperRun.create!(source: @source, run_type: "recheck", status: "failed", started_at: 1.hour.ago, finished_at: 1.hour.ago, created_at: 1.hour.ago)

    refute @job.send(:recheck_due?, @source)
  end

  test "recheck becomes due again after the backoff interval" do
    ScraperRun.create!(source: @source, run_type: "recheck", status: "failed", started_at: 7.hours.ago, finished_at: 7.hours.ago, created_at: 7.hours.ago)

    assert @job.send(:recheck_due?, @source)
  end

  test "sweep heals a broken source whose recheck succeeds" do
    # A pre-recorded successful recheck stands in for the probe so the sweep
    # itself makes no network requests for this unregistered key.
    ScraperRun.create!(source: @source, run_type: "recheck", status: "success", started_at: 1.minute.ago, finished_at: 1.minute.ago, created_at: 1.minute.ago)

    SourceHealthSweepJob.perform_now

    assert_equal "healthy", @source.reload.health_status
  end

  test "sweep leaves healthy sources alone and probes nothing for them" do
    healthy = Source.create!(key: "sweep_healthy", name: "Sweep Healthy", base_url: "https://example.test")

    SourceHealthSweepJob.perform_now

    assert_equal 0, healthy.scraper_runs.where(run_type: "recheck").count
    assert_equal "healthy", healthy.reload.health_status
  end
end
