# frozen_string_literal: true

# Configure secure session cookies
Rails.application.config.session_store :cookie_store,
  key: "_scanarr_session",
  httponly: true,                          # JavaScript cannot access this cookie
  secure: Rails.env.production?,           # Only send over HTTPS in production
  same_site: :lax,                         # CSRF protection
  expire_after: 30.days                    # Session expires after 30 days of inactivity
