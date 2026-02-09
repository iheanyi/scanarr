# frozen_string_literal: true

# Treat app/scrapers as a namespace root for Scrapers::* constants.
module Scrapers
end

Rails.autoloaders.main.push_dir(
  Rails.root.join("app/scrapers"),
  namespace: Scrapers
)
