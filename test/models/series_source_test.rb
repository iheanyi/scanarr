require "test_helper"

class SeriesSourceTest < ActiveSupport::TestCase
  def setup
    @series_source = series_sources(:one)
  end

  def test_allows_library_base_path
    @series_source.update!(library_base_path: "weeb_central/one-piece-eiichiro-oda")

    assert_equal "weeb_central/one-piece-eiichiro-oda", @series_source.library_base_path
  end

  # --- Error Tracking ---

  def test_record_check_success_clears_errors
    @series_source.update!(
      consecutive_failures: 3,
      last_check_error: "connection timeout",
      last_check_error_at: 1.hour.ago
    )

    @series_source.record_check_success!

    assert_equal 0, @series_source.consecutive_failures
    assert_nil @series_source.last_check_error
    assert_nil @series_source.last_check_error_at
    assert_in_delta Time.current, @series_source.last_checked_at, 5.seconds
  end

  def test_record_check_failure_increments_consecutive_failures
    assert_equal 0, @series_source.consecutive_failures

    @series_source.record_check_failure!("connection timeout")

    assert_equal 1, @series_source.consecutive_failures
    assert_equal "connection timeout", @series_source.last_check_error
    assert_in_delta Time.current, @series_source.last_check_error_at, 5.seconds
  end

  def test_record_check_failure_accumulates
    @series_source.record_check_failure!("error 1")
    @series_source.record_check_failure!("error 2")

    assert_equal 2, @series_source.consecutive_failures
    assert_equal "error 2", @series_source.last_check_error
  end

  def test_record_check_failure_truncates_long_messages
    long_message = "x" * 600

    @series_source.record_check_failure!(long_message)

    assert_operator @series_source.last_check_error.length, :<=, 500
  end

  def test_check_failing_returns_true_when_failures_present
    @series_source.update!(consecutive_failures: 1)

    assert_predicate @series_source, :check_failing?
  end

  def test_check_failing_returns_false_when_no_failures
    assert_not @series_source.check_failing?
  end

  def test_check_critically_failing_at_threshold
    @series_source.update!(consecutive_failures: 3)

    assert_predicate @series_source, :check_critically_failing?
  end

  def test_check_critically_failing_below_threshold
    @series_source.update!(consecutive_failures: 2)

    assert_not @series_source.check_critically_failing?
  end

  def test_stale_at_threshold
    @series_source.update!(consecutive_failures: 10)

    assert_predicate @series_source, :stale?
  end

  def test_stale_below_threshold
    @series_source.update!(consecutive_failures: 9)

    assert_not @series_source.stale?
  end

  # --- Scopes ---

  def test_with_errors_scope
    @series_source.update!(last_check_error: "some error")

    assert_includes SeriesSource.with_errors, @series_source
    assert_not_includes SeriesSource.healthy, @series_source
  end

  def test_healthy_scope
    @series_source.update!(last_check_error: nil)

    assert_includes SeriesSource.healthy, @series_source
    assert_not_includes SeriesSource.with_errors, @series_source
  end

  def test_needs_attention_scope
    @series_source.update!(consecutive_failures: 5)

    assert_includes SeriesSource.needs_attention, @series_source
  end

  def test_needs_attention_excludes_stale
    @series_source.update!(consecutive_failures: 10)

    assert_not_includes SeriesSource.needs_attention, @series_source
    assert_includes SeriesSource.stale, @series_source
  end
end
