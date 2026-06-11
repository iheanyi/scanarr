require "test_helper"

module Sources
  class HealthEvaluatorTest < ActiveSupport::TestCase
    setup do
      @source = Source.create!(key: "health_probe", name: "Health Probe", base_url: "https://example.test")
    end

    test "healthy with no signals" do
      assert_equal "healthy", HealthEvaluator.new(@source).derived_status
    end

    test "degraded after a single failed smoke run" do
      create_run("failed")

      assert_equal "degraded", HealthEvaluator.new(@source).derived_status
    end

    test "broken after three consecutive failed smoke runs" do
      3.times { |i| create_run("failed", at: i.minutes.ago) }

      assert_equal "broken", HealthEvaluator.new(@source).derived_status
    end

    test "a failed recovery probe cannot demote broken to degraded" do
      @source.update!(health_status: "broken")
      create_run("failed")

      # Degraded would resume chapter fan-out and end recovery probing
      assert_equal "broken", HealthEvaluator.new(@source).derived_status
    end

    test "recovers to healthy when the latest run succeeds" do
      3.times { |i| create_run("failed", at: (i + 1).minutes.ago) }
      create_run("success", at: Time.current)

      assert_equal "healthy", HealthEvaluator.new(@source).derived_status
    end

    test "version bump windows out old failures" do
      3.times { |i| create_run("failed", at: (i + 10).minutes.ago) }
      @source.update!(adapter_version_synced_at: 5.minutes.ago)

      assert_equal "healthy", HealthEvaluator.new(@source).derived_status
    end

    test "broken when most tracked series are critically failing" do
      4.times do |i|
        series = create_series("Failing #{i}")
        SeriesSource.create!(
          series: series,
          source: @source,
          source_series_id: "FAIL#{i}",
          last_checked_at: Time.current,
          last_check_error: "boom",
          last_check_error_at: Time.current,
          consecutive_failures: 5
        )
      end

      assert_equal "broken", HealthEvaluator.new(@source).derived_status
    end

    test "series whose checks have only ever failed still count as broken evidence" do
      4.times do |i|
        series = create_series("Never Succeeded #{i}")
        SeriesSource.create!(
          series: series,
          source: @source,
          source_series_id: "NEVER#{i}",
          last_checked_at: nil,
          last_check_error: "boom",
          last_check_error_at: Time.current,
          consecutive_failures: 5
        )
      end

      assert_equal "broken", HealthEvaluator.new(@source).derived_status
    end

    test "stale pre-window series do not dilute the failure ratio" do
      @source.update!(adapter_version_synced_at: 1.hour.ago)

      # Old attempts from before the evidence window
      4.times do |i|
        series = create_series("Stale OK #{i}")
        SeriesSource.create!(
          series: series, source: @source, source_series_id: "OLD#{i}",
          last_checked_at: 2.days.ago, consecutive_failures: 0
        )
      end
      # Every series actually attempted since the window opened is failing
      4.times do |i|
        series = create_series("Fresh Fail #{i}")
        SeriesSource.create!(
          series: series, source: @source, source_series_id: "FRESH#{i}",
          last_check_error: "boom", last_check_error_at: Time.current, consecutive_failures: 5
        )
      end

      assert_equal "broken", HealthEvaluator.new(@source).derived_status
    end

    test "a successful run outweighs older series failures so a healed source recovers" do
      4.times do |i|
        series = create_series("Stale Failure #{i}")
        SeriesSource.create!(
          series: series,
          source: @source,
          source_series_id: "STALE#{i}",
          last_checked_at: 2.hours.ago,
          last_check_error: "boom",
          last_check_error_at: 2.hours.ago,
          consecutive_failures: 5
        )
      end

      assert_equal "broken", HealthEvaluator.new(@source).derived_status

      create_run("success", at: Time.current)

      assert_equal "healthy", HealthEvaluator.new(@source).derived_status
    end

    test "healing from degraded also un-stales series" do
      @source.update!(health_status: "degraded")
      series = create_series("Minority Stale")
      stale = SeriesSource.create!(
        series: series, source: @source, source_series_id: "STALE_MINORITY",
        last_checked_at: 2.hours.ago, consecutive_failures: 12
      )
      create_run("success", at: Time.current)

      assert_equal "healthy", HealthEvaluator.new(@source).call
      assert_equal 0, stale.reload.consecutive_failures
    end

    test "degraded when rate limited" do
      @source.update!(rate_limited_until: 10.minutes.from_now)

      assert_equal "degraded", HealthEvaluator.new(@source).derived_status
    end

    test "dead status is preserved and never derived away" do
      @source.update!(health_status: "dead")
      create_run("success")

      assert_equal "dead", HealthEvaluator.new(@source).derived_status
    end

    test "call persists the status idempotently" do
      create_run("failed")

      evaluator_status = HealthEvaluator.new(@source).call
      first_changed_at = @source.reload.health_changed_at

      assert_equal "degraded", evaluator_status
      assert_equal "degraded", @source.health_status

      HealthEvaluator.new(@source.reload).call

      assert_equal first_changed_at, @source.reload.health_changed_at
    end

    private

    def create_run(status, at: Time.current)
      ScraperRun.create!(
        source: @source,
        run_type: "smoke",
        status: status,
        started_at: at,
        finished_at: at,
        created_at: at
      )
    end

    def create_series(title)
      library = LibrarySeries.create!(canonical_title: title, status: "ongoing")
      Series.create!(canonical_title: title, library_series: library)
    end
  end
end
