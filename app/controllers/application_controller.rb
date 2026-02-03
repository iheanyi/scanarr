class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  # HTTP Basic Auth - credentials from env vars with sensible defaults
  before_action :authenticate!

  helper_method :current_user, :user_signed_in?, :current_notifications, :unread_notification_count

  private

  # HTTP Basic Auth credentials
  def auth_username
    ENV.fetch("SCANARR_USERNAME", "scanarr")
  end

  def auth_password
    ENV.fetch("SCANARR_PASSWORD", "ilovemanga")
  end

  def authenticate!
    authenticate_or_request_with_http_basic("Scanarr") do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, auth_username) &&
        ActiveSupport::SecurityUtils.secure_compare(password, auth_password)
    end
  end

  # Returns the admin user (auto-created if needed)
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_or_create_by!(email: "admin@scanarr.local")
  end

  def user_signed_in?
    true # Always signed in after HTTP Basic Auth passes
  end

  def current_notifications
    @current_notifications ||= current_user.new_chapter_notifications
      .includes(chapter: { series: :sources })
      .unread
      .recent
      .order(created_at: :desc)
      .limit(10)
  end

  def unread_notification_count
    @unread_notification_count ||= current_user.new_chapter_notifications.unread.count
  end
end
