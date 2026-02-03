require "test_helper"

class ChapterProgressTest < ActiveSupport::TestCase
  def test_requires_user_and_chapter
    progress = ChapterProgress.new(page_index: 1, page_count: 10, status: "in_progress")
    assert_not progress.valid?
    assert_includes progress.errors[:user], "must exist"
    assert_includes progress.errors[:chapter], "must exist"
  end

  def test_enforces_unique_user_chapter
    user = User.create!(email: "reader@example.com", password: "password123", password_confirmation: "password123")
    chapter = chapters(:one)

    ChapterProgress.create!(
      user: user,
      chapter: chapter,
      page_index: 1,
      page_count: 10,
      status: "in_progress",
      progressed_at: Time.current
    )
    duplicate = ChapterProgress.new(
      user: user,
      chapter: chapter,
      page_index: 2,
      page_count: 10,
      status: "in_progress",
      progressed_at: Time.current
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:chapter_id], "has already been taken"
  end

  def test_requires_page_fields
    user = User.create!(email: "reader2@example.com", password: "password123", password_confirmation: "password123")
    chapter = chapters(:one)

    progress = ChapterProgress.new(user: user, chapter: chapter, status: "in_progress", progressed_at: Time.current)
    assert_not progress.valid?
    assert_includes progress.errors[:page_index], "can't be blank"
    assert_includes progress.errors[:page_count], "can't be blank"
  end
end
