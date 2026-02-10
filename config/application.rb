require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Scanarr
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.autoload_paths << Rails.root.join("app/components")
    config.eager_load_paths << Rails.root.join("app/components")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Use vips for image variant processing (faster, lower memory than ImageMagick).
    # Requires libvips: `brew install vips` on macOS, `apt install libvips-dev` on Linux.
    # Falls back gracefully if unavailable — original images are served instead.
    config.active_storage.variant_processor = :vips

    # Enable full-stack Rails for Hotwire/Stimulus UI.
    config.api_only = false

    # Use our own controller for error pages (404, 422, 500)
    # so Turbo Drive gets proper HTML responses instead of "invalid response"
    config.exceptions_app = routes
  end
end
