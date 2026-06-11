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

  # --- Content Rating ---

  def test_mature_content_defaults_to_false
    assert_not @source.mature_content?
  end

  def test_effective_base_url_falls_back_for_unregistered_sources
    # example_source has no manifest entry, so the registry returns nil and
    # the model falls back to its own columns
    unregistered = sources(:two)
    unregistered.update!(base_url: "https://canonical.example")

    assert_equal "https://canonical.example", unregistered.effective_base_url

    unregistered.update!(adopted_base_url: "https://moved.example")

    assert_equal "https://moved.example", unregistered.effective_base_url
  end

  def test_mature_content_uses_capabilities_override
    @source.update!(capabilities: { mature_content: true })

    assert_predicate @source, :mature_content?
  end

  def test_mature_content_falls_back_to_known_mature_key
    source = Source.new(key: "manhwa18", name: "Manhwa18")

    assert_predicate source, :mature_content?
  end

  def test_display_name_with_content_rating_appends_flag_for_mature_source
    source = Source.new(key: "manhwa18", name: "Manhwa18")

    assert_equal "Manhwa18 (18+)", source.display_name_with_content_rating
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
