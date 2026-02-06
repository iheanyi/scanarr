# frozen_string_literal: true

require "test_helper"

class CleanOldNotificationsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @chapter = chapters(:one)
  end

  test "deletes read notifications older than 30 days" do
    old_read = NewChapterNotification.create!(user: @user, chapter: @chapter, read: true, created_at: 31.days.ago)
    recent_read = NewChapterNotification.create!(user: @user, chapter: chapters(:two), read: true, created_at: 5.days.ago)

    CleanOldNotificationsJob.perform_now

    assert_not NewChapterNotification.exists?(old_read.id)
    assert NewChapterNotification.exists?(recent_read.id)
  end

  test "preserves unread notifications less than 90 days old" do
    old_unread = NewChapterNotification.create!(user: @user, chapter: @chapter, read: false, created_at: 60.days.ago)

    CleanOldNotificationsJob.perform_now

    assert NewChapterNotification.exists?(old_unread.id)
  end

  test "deletes all notifications older than 90 days" do
    very_old_unread = NewChapterNotification.create!(user: @user, chapter: @chapter, read: false, created_at: 91.days.ago)
    very_old_read = NewChapterNotification.create!(user: @user, chapter: chapters(:two), read: true, created_at: 91.days.ago)

    CleanOldNotificationsJob.perform_now

    assert_not NewChapterNotification.exists?(very_old_unread.id)
    assert_not NewChapterNotification.exists?(very_old_read.id)
  end
end
