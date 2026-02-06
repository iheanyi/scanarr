# frozen_string_literal: true

class NotificationsController < ApplicationController
  # Authentication handled by ApplicationController

  def index
    @notifications = current_user.new_chapter_notifications
      .includes(chapter: { series: [ :sources, :cover_attachment ] })
      .order(created_at: :desc)
      .limit(50)
  end

  def mark_read
    @notification = current_user.new_chapter_notifications.includes(chapter: { series: [ :sources, :cover_attachment ] }).find(params[:id])
    @notification.mark_as_read!

    respond_to do |format|
      format.html { redirect_back fallback_location: notifications_path }
      format.turbo_stream
    end
  end

  def mark_all_read
    current_user.new_chapter_notifications.unread.update_all(read: true)

    respond_to do |format|
      format.html { redirect_back fallback_location: notifications_path, notice: "All notifications marked as read" }
      format.turbo_stream
    end
  end
end
