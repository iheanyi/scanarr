class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  helper_method :current_notifications, :unread_notification_count

  private

  def current_notifications
    return [] unless user_signed_in?

    @current_notifications ||= current_user.new_chapter_notifications
      .includes(chapter: { series: :sources })
      .unread
      .recent
      .order(created_at: :desc)
      .limit(10)
  end

  def unread_notification_count
    return 0 unless user_signed_in?

    @unread_notification_count ||= current_user.new_chapter_notifications.unread.count
  end
end
