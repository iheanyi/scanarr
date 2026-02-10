require "test_helper"

class UserPreferencesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "prefs-test@scanarr.local", username: "prefs_test_user")
  end

  def test_effective_reading_style_defaults_to_left_to_right
    assert_equal "left_to_right", @user.effective_reading_style
  end

  def test_effective_reading_style_returns_set_value
    @user.update!(default_reading_style: "right_to_left")

    assert_equal "right_to_left", @user.effective_reading_style
  end

  def test_effective_download_policy_defaults_to_auto_download
    assert_equal "auto_download", @user.effective_download_policy
  end

  def test_effective_download_policy_returns_set_value
    @user.update!(default_download_policy: "auto_download")

    assert_equal "auto_download", @user.effective_download_policy
  end

  def test_effective_check_interval_defaults_to_30
    assert_equal 30, @user.effective_check_interval_minutes
  end

  def test_effective_check_interval_returns_set_value
    @user.update!(default_check_interval_minutes: "60")

    assert_equal 60, @user.effective_check_interval_minutes
  end

  def test_notifications_enabled_defaults_to_true
    assert_predicate @user, :notifications_enabled?
  end

  def test_notifications_can_be_disabled
    @user.update!(notifications_enabled: "false")

    assert_not @user.notifications_enabled?
  end

  def test_notifications_can_be_re_enabled
    @user.update!(notifications_enabled: "false")
    @user.update!(notifications_enabled: "true")

    assert_predicate @user, :notifications_enabled?
  end

  def test_effective_cleanup_days_defaults_to_nil
    assert_nil @user.effective_cleanup_days
  end

  def test_effective_cleanup_days_returns_set_value
    @user.update!(notification_auto_cleanup_days: "30")

    assert_equal 30, @user.effective_cleanup_days
  end

  def test_preferences_persist_via_jsonb
    @user.update!(
      default_reading_style: "webcomic",
      default_download_policy: "auto_download",
      notifications_enabled: "false"
    )

    reloaded = User.find(@user.id)

    assert_equal "webcomic", reloaded.default_reading_style
    assert_equal "auto_download", reloaded.default_download_policy
    assert_not reloaded.notifications_enabled?
  end
end
