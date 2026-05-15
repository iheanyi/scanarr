module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :redirect_to_setup
    before_action :require_authentication
    helper_method :authenticated?, :current_user, :user_signed_in?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :redirect_to_setup, **options
    end
  end

  private

  def redirect_to_setup
    return if auth_disabled?
    return if controller_name == "setup"
    unless setup_complete?
      redirect_to setup_path
    end
  end

  # Cache the setup check — after initial setup, this is always true
  # and never needs to hit the database again.
  def setup_complete?
    @@setup_complete = nil unless defined?(@@setup_complete) # rubocop:disable Style/ClassVars
    @@setup_complete ||= User.where.not(password_digest: nil).exists? # rubocop:disable Style/ClassVars
  end

  def self.reset_setup_cache!
    @@setup_complete = nil # rubocop:disable Style/ClassVars
  end

  def auth_disabled?
    ENV["SCANARR_DISABLE_AUTH"] == "true"
  end

  def authenticated?
    Current.session.present?
  end

  alias_method :user_signed_in?, :authenticated?

  def current_user
    Current.user || auto_login_user
  end

  def require_authentication
    return if auth_disabled? && ensure_auto_login
    return authenticate_via_api_key if api_key_request?

    resume_session || request_authentication
  end

  def api_key_request?
    request.headers["X-Api-Key"].present?
  end

  def resume_session
    if (session_record = find_session_by_cookie)
      set_current_session(session_record)
    end
  end

  def find_session_by_cookie
    if (token = cookies.signed[:session_token])
      Session.find_by(token: token)
    end
  end

  def start_new_session_for(user)
    user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session_record|
      set_current_session(session_record)
    end
  end

  def set_current_session(session_record)
    Current.session = session_record
    cookies.signed.permanent[:session_token] = {
      value: session_record.token, httponly: true, same_site: :lax
    }
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(:session_token)
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url
    redirect_to login_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def authenticate_via_api_key
    if (api_key = request.headers["X-Api-Key"]).present?
      if (user = User.find_by(api_key: api_key))
        start_new_session_for(user)
      else
        render json: { error: "Invalid API key" }, status: :unauthorized
      end
    end
  end

  def require_admin
    return if current_user&.admin?
    redirect_to root_path, alert: "You don't have permission to access that page."
  end

  def ensure_auto_login
    return false unless auth_disabled?
    return true if Current.session.present?
    user = auto_login_user
    start_new_session_for(user) if user
    true
  end

  def auto_login_user
    return nil unless auth_disabled?

    User.first || create_auto_login_user
  end

  def create_auto_login_user
    User.new(
      email: "admin@scanarr.local",
      username: "admin",
      role: :admin
    ).tap { |user| user.save!(validate: false) }
  end
end
