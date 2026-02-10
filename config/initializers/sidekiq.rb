# frozen_string_literal: true

require "sidekiq"
require "sidekiq/cron/job"

module SidekiqRuntimeConfig
  module_function

  def sidekiq_redis_url
    ENV.fetch("SIDEKIQ_REDIS_URL", ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/1"))
  end

  def redis_options
    {
      url: sidekiq_redis_url,
      network_timeout: 5
    }
  end
end

Sidekiq.configure_client do |config|
  config.redis = SidekiqRuntimeConfig.redis_options
end

Sidekiq.configure_server do |config|
  config.redis = SidekiqRuntimeConfig.redis_options
  config[:tag] = ENV.fetch("SIDEKIQ_TAG", "scanarr-#{Rails.env}")

  schedule_path = Rails.root.join("config/sidekiq_schedule.yml")
  next unless schedule_path.exist?

  all_schedules = YAML.safe_load(schedule_path.read, aliases: true) || {}
  schedule_for_env = all_schedules.fetch(Rails.env, {})
  Sidekiq::Cron::Job.load_from_hash!(schedule_for_env) if schedule_for_env.any?
end
