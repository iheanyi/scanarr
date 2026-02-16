require "test_helper"

class UserOfflineManifestEntryTest < ActiveSupport::TestCase
  def test_defaults_status_to_pinned
    entry = UserOfflineManifestEntry.create!(user: users(:admin), chapter: chapters(:one))

    assert_equal "pinned", entry.status
  end

  def test_validates_unique_chapter_per_user
    UserOfflineManifestEntry.create!(user: users(:admin), chapter: chapters(:one))
    duplicate = UserOfflineManifestEntry.new(user: users(:admin), chapter: chapters(:one))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:chapter_id], "has already been taken"
  end

  def test_rejects_unknown_status
    entry = UserOfflineManifestEntry.new(
      user: users(:admin),
      chapter: chapters(:one),
      status: "unknown"
    )

    assert_not entry.valid?
  end
end
