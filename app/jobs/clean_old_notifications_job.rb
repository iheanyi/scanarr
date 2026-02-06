# frozen_string_literal: true

class CleanOldNotificationsJob < ApplicationJob
  queue_as :default

  def perform
    # Delete read notifications older than 30 days
    NewChapterNotification.where(read: true)
      .where("created_at < ?", 30.days.ago)
      .delete_all

    # Delete all notifications older than 90 days regardless of read status
    NewChapterNotification.where("created_at < ?", 90.days.ago)
      .delete_all
  end
end
