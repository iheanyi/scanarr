require "active_support/core_ext/integer/time"
require "uri"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.
  env_list = ->(name) { ENV.fetch(name, "").split(/[,\s]+/).map(&:strip).reject(&:empty?) }
  env_enabled = ->(name) { ENV.fetch(name, "false").match?(/\A(true|1|yes|on)\z/i) }

  app_url = ENV.fetch("APP_URL", "").strip
  app_uri = if app_url.empty?
    nil
  else
    URI.parse(app_url)
  end

  app_host = ENV.fetch("APP_HOST", "").strip
  app_host = app_uri.host.to_s if app_host.empty? && app_uri

  app_protocol = ENV.fetch("APP_PROTOCOL", "").strip
  app_protocol = app_uri.scheme.to_s if app_protocol.empty? && app_uri
  app_protocol = env_enabled.call("RAILS_FORCE_SSL") ? "https" : "http" if app_protocol.empty?

  app_port = ENV.fetch("APP_PORT", "").strip
  app_port = app_uri.port.to_s if app_port.empty? && app_uri && ![ 80, 443 ].include?(app_uri.port)

  default_url_options = if app_host.empty?
    {}
  else
    options = { host: app_host, protocol: "#{app_protocol}://" }
    options[:port] = app_port.to_i if app_port.match?(/\A\d+\z/)
    options
  end

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files through Active Storage. Use ACTIVE_STORAGE_SERVICE=s3
  # with S3_* env vars for AWS S3, Cloudflare R2, MinIO, or another S3-compatible service.
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym

  # Serve files directly (proxy) instead of redirecting, saving an HTTP roundtrip per image.
  # Also allows proper Cache-Control headers on the served content.
  config.active_storage.resolve_model_to_route = :rails_storage_proxy

  # Configure reverse-proxy SSL behavior with env vars so Compose, Kamal,
  # Caddy, Cloudflare Tunnel, and local-only homelab installs can share one image.
  config.assume_ssl = true if env_enabled.call("RAILS_ASSUME_SSL") || env_enabled.call("RAILS_FORCE_SSL")

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true if env_enabled.call("RAILS_FORCE_SSL")

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } } if env_enabled.call("RAILS_FORCE_SSL")

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Use Redis for shared cache.
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"),
    namespace: ENV.fetch("REDIS_CACHE_NAMESPACE", "scanarr:cache:production")
  }

  # Use Sidekiq for background jobs.
  config.active_job.queue_adapter = :sidekiq

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by generated links.
  config.action_controller.default_url_options = default_url_options
  config.action_mailer.default_url_options = default_url_options
  Rails.application.routes.default_url_options = default_url_options

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks when hosts
  # are configured. RAILS_HOSTS accepts comma- or space-separated hosts. Regex
  # values may be written as /pattern/.
  configured_hosts = env_list.call("RAILS_HOSTS")
  configured_hosts << app_host if app_host.present?
  configured_hosts.uniq.each do |host|
    config.hosts << if host.start_with?("/") && host.end_with?("/") && host.length > 2
      Regexp.new(host[1...-1])
    else
      host
    end
  end
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } } if configured_hosts.any?

  cable_origins = env_list.call("ACTION_CABLE_ALLOWED_REQUEST_ORIGINS")
  if app_host.present?
    host_with_port = app_port.match?(/\A\d+\z/) ? "#{app_host}:#{app_port}" : app_host
    cable_origins << "#{app_protocol}://#{host_with_port}"
  end
  config.action_cable.allowed_request_origins = cable_origins.uniq if cable_origins.any?
end
