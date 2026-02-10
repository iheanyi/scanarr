# frozen_string_literal: true

# Treat app/scrapers as a namespace root for Scrapers::* constants.
module Scrapers
end

Rails.autoloaders.main.push_dir(
  Rails.root.join("app/scrapers"),
  namespace: Scrapers
)

# Compatibility aliases for bare constant references (e.g., AdapterRegistry instead of Scrapers::AdapterRegistry).
# Force-load these constants after initialization so the side-effect aliases in each file are executed.
# This ensures ::AdapterRegistry, ::ResultTypes, and ::HttpClient are available before any code references them,
# which is critical in non-eager-load environments (local dev/test without CI=true).
Rails.application.config.after_initialize do
  Scrapers::AdapterRegistry
  Scrapers::ResultTypes
  Scrapers::HttpClient
end
