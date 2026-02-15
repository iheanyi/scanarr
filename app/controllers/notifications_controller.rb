# frozen_string_literal: true

class NotificationsController < ApplicationController
  # Authentication handled by ApplicationController
  before_action :set_notification, only: :mark_read

  def index
    @notifications = current_user.new_chapter_notifications
      .includes(chapter: { series: [ :sources, { cover_attachment: :blob } ] })
      .order(created_at: :desc)
      .limit(50)
  end

  def mark_read
    @notification.mark_as_read!

    respond_to do |format|
      format.html { redirect_back fallback_location: notifications_path, notice: "Notification marked as read" }
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

  private

  def set_notification
    @notification = current_user.new_chapter_notifications
                                .includes(chapter: { series: [ :sources, { cover_attachment: :blob } ] })
                                .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_with_toast(
      redirect_path: notifications_path,
      message: "Notification not found",
      variant: :danger,
      status: :not_found,
      turbo_redirect: true
    )
    nil
  end
end
