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

    assert follow.notify_only?
    assert_not follow.auto_download?

    follow.update!(download_policy: :auto_download)
    assert follow.auto_download?
    assert_not follow.notify_only?
  end

  def test_auto_download_helper
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)

    assert_not follow.auto_download?

    follow.update!(download_policy: :auto_download)
    assert follow.auto_download?
  end

  def test_uniqueness_of_user_and_library_series
    UserSeriesFollow.create!(user: @user, library_series: @library_series)

    duplicate = UserSeriesFollow.new(user: @user, library_series: @library_series)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  def test_source_priority_defaults_to_empty_array
    follow = UserSeriesFollow.create!(user: @user, library_series: @library_series)
    assert_equal [], follow.source_priority
  end

  def test_source_priority_stores_jsonb
    follow = UserSeriesFollow.create!(
      user: @user,
      library_series: @library_series,
      source_priority: ["mangadex", "comick", "mangasee"]
    )

    assert_equal ["mangadex", "comick", "mangasee"], follow.source_priority
  end
end
