# frozen_string_literal: true

require "test_helper"

class SourceTest < ActiveSupport::TestCase
  def setup
    @source = sources(:one)
  end

  # --- Rate Limiting ---

  def test_rate_limited_returns_false_when_no_rate_limit
    assert_not @source.rate_limited?
  end

  def test_rate_limited_returns_false_when_expired
    @source.update!(rate_limited_until: 1.minute.ago)

    assert_not @source.rate_limited?
  end

  def test_rate_limited_returns_true_when_active
    @source.update!(rate_limited_until: 5.minutes.from_now)

    assert_predicate @source, :rate_limited?
  end

  def test_record_rate_limit_sets_future_time
    @source.record_rate_limit!(10.minutes)

    assert_predicate @source, :rate_limited?
    assert_in_delta 10.minutes.from_now, @source.rate_limited_until, 5.seconds
  end

  def test_record_rate_limit_defaults_to_five_minutes
    @source.record_rate_limit!

    assert_predicate @source, :rate_limited?
    assert_in_delta 5.minutes.from_now, @source.rate_limited_until, 5.seconds
  end

  def test_clear_rate_limit_removes_rate_limit
    @source.update!(rate_limited_until: 5.minutes.from_now)

    assert_predicate @source, :rate_limited?

    @source.clear_rate_limit!

    assert_not @source.rate_limited?
    assert_nil @source.rate_limited_until
  end

  def test_clear_rate_limit_is_noop_when_not_rate_limited
    assert_nil @source.rate_limited_until

    assert_nothing_raised do
      @source.clear_rate_limit!
    end
  end

  # --- Slug Generation ---

  def test_generates_slug_from_key
    source = Source.new(key: "my_source", name: "My Source")
    source.valid?

    assert_equal "my-source", source.slug
  end

  def test_validates_key_uniqueness
    duplicate = Source.new(key: @source.key, name: "Duplicate")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end
end
