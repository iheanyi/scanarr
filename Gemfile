source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# HTML parsing for scrapers
gem "nokogiri", "~> 1.16"
# HTTP client for scrapers
gem "faraday"
gem "faraday-retry"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Additional RuboCop extensions
  gem "rubocop-performance", require: false
  gem "rubocop-minitest", require: false

  # ERB template linting [https://github.com/Shopify/erb_lint]
  gem "erb_lint", require: false

  # Record and replay HTTP for scraper tests
  gem "vcr"
  gem "webmock"
end

gem "nanoid", "~> 2.0"

gem "jsbundling-rails", "~> 1.3"
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"
gem "friendly_id", "~> 5.6"

gem "rubyzip", "~> 3.2"


gem "propshaft", "~> 1.3"

gem "kaminari", "~> 1.2"

gem "bullet", "~> 8.1", groups: [ :development, :test ]

gem "mission_control-jobs", "~> 1.1"

gem "view_component"
