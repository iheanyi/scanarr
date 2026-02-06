require "test_helper"

class UserSeriesFollowTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "test@example.com")
    @library_series = LibrarySeries.create!(canonical_title: "One Piece")
  end

  def test_belongs_to_user_and_library_series
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)

    assert_equal @user, follow.user
    assert_equal @library_series, follow.library_series
  end

  def test_download_policy_enum
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)

    assert_predicate follow, :notify_only?
    assert_not follow.auto_download?

    follow.update!(download_policy: :auto_download)

    assert_predicate follow, :auto_download?
    assert_not follow.notify_only?
  end

  def test_auto_download_helper
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)

    assert_not follow.auto_download?

    follow.update!(download_policy: :auto_download)

    assert_predicate follow, :auto_download?
  end

  def test_uniqueness_of_user_and_library_series
    UserSeriesFollow.create!(user: @user, library_series: @library_series)

    duplicate = UserSeriesFollow.new(user: @user, library_series: @library_series)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  def test_source_priority_defaults_to_empty_array
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)

    assert_empty follow.source_priority
  end

  def test_source_priority_stores_jsonb
    follow = UserSeriesFollow.create!(
      user: @user,
      library_series: @library_series,
      source_priority: %w[mangadex comick mangasee]
    )

    assert_equal %w[mangadex comick mangasee], follow.source_priority
  end

  # --- Phase 3: Smart Scheduling ---

  def test_check_interval_minutes_defaults_to_nil
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)

    assert_nil follow.check_interval_minutes
  end

  def test_check_interval_minutes_stores_valid_values
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series, check_interval_minutes: 60)

    assert_equal 60, follow.check_interval_minutes
  end

  def test_check_interval_minutes_validates_allowed_values
    follow = UserSeriesFollow.new(user: @user, library_series: @library_series, check_interval_minutes: 42)

    assert_not follow.valid?
    assert_includes follow.errors[:check_interval_minutes], "is not included in the list"
  end

  def test_effective_interval_minutes_returns_custom_value
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series, check_interval_minutes: 720)

    assert_equal 720, follow.effective_interval_minutes
  end

  def test_effective_interval_minutes_returns_default_when_nil
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)

    assert_equal 30, follow.effective_interval_minutes
  end

  def test_needs_check_returns_true_when_never_checked
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)
    series_source = SeriesSource.new(last_checked_at: nil)

    assert follow.needs_check?(series_source)
  end

  def test_needs_check_returns_true_when_past_interval
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series, check_interval_minutes: 30)
    series_source = SeriesSource.new(last_checked_at: 31.minutes.ago)

    assert follow.needs_check?(series_source)
  end

  def test_needs_check_returns_false_when_within_interval
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series, check_interval_minutes: 60)
    series_source = SeriesSource.new(last_checked_at: 30.minutes.ago)

    assert_not follow.needs_check?(series_source)
  end

  def test_interval_options_constant
    assert_equal 7, UserSeriesFollow::INTERVAL_OPTIONS.size
    assert_equal [ "Use default (30 min)", nil ], UserSeriesFollow::INTERVAL_OPTIONS.first
    assert_equal [ "Daily", 1440 ], UserSeriesFollow::INTERVAL_OPTIONS.last
  end

  def test_preferred_source_for_returns_default_when_no_priority
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)
    default_source = sources(:one)
    chapter = chapters(:one) if respond_to?(:chapters)
    chapter ||= series(:one).chapters.first

    # If no chapter exists, skip
    skip unless chapter

    assert_equal default_source, follow.preferred_source_for(chapter, default_source)
  end
end
