class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  before_action :authenticate!

  helper_method :current_user, :user_signed_in?, :authenticated?, :current_notifications, :unread_notification_count

  private

  # Auth credentials from env vars with sensible defaults
  def auth_username
    ENV.fetch("SCANARR_USERNAME", "scanarr")
  end

  def auth_password
    ENV.fetch("SCANARR_PASSWORD", "ilovemanga")
  end

  def authenticated?
    session[:authenticated] == true
  end

  def authenticate!
    return if authenticated?

    # Fall back to HTTP Basic Auth for API clients/curl
    if request.authorization.present?
      if valid_http_basic_auth?
        session[:authenticated] = true
        return
      else
        request_http_basic_authentication("Scanarr")
        return
      end
    end

    redirect_to login_path
  end

  def valid_http_basic_auth?
    authenticate_with_http_basic { |u, p| valid_credentials?(u, p) }
  end

  def valid_credentials?(username, password)
    return false if username.blank? || password.blank?

    ActiveSupport::SecurityUtils.secure_compare(username.to_s, auth_username) &&
      ActiveSupport::SecurityUtils.secure_compare(password.to_s, auth_password)
  end

  # Returns the admin user (auto-created if needed)
  def current_user
    return @current_user if defined?(@current_user)
    return nil unless authenticated?

    @current_user = User.find_or_create_by!(email: "admin@scanarr.local")
  end

  def user_signed_in?
    authenticated?
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
