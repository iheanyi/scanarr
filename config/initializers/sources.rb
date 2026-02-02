require "yaml"

sources_path = Rails.root.join("config/sources.yml")
if sources_path.exist?
  raw_config = YAML.load_file(sources_path, aliases: true)
  env_config = raw_config.fetch(Rails.env, {})
  Rails.application.config.scraper_sources = env_config
else
  Rails.application.config.scraper_sources = {}
end
