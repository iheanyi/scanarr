namespace :queue do
  def process_lines(processes)
    processes.map { |process| "- #{process["hostname"]}:#{process["pid"]}" }
  end

  def configured_cron_jobs
    schedule_path = Rails.root.join("config/sidekiq_schedule.yml")
    return {} unless schedule_path.exist?

    all_schedules = YAML.safe_load(schedule_path.read, aliases: true) || {}
    all_schedules.fetch(Rails.env, {})
  end

  desc "Print Sidekiq/Redis health stats"
  task health: :environment do
    require "sidekiq/api"
    require "sidekiq/cron/job"

    begin
      Sidekiq.redis(&:ping)

      queue = Sidekiq::Queue.new("default")
      retry_set = Sidekiq::RetrySet.new
      dead_set = Sidekiq::DeadSet.new
      scheduled_set = Sidekiq::ScheduledSet.new
      process_set = Sidekiq::ProcessSet.new.to_a
      cron_jobs = Sidekiq::Cron::Job.all
      configured_jobs = configured_cron_jobs

      puts "Redis: OK"
      puts "default queue size: #{queue.size}"
      puts "scheduled jobs: #{scheduled_set.size}"
      puts "retry jobs: #{retry_set.size}"
      puts "dead jobs: #{dead_set.size}"
      puts "sidekiq processes: #{process_set.size}"
      puts "cron jobs loaded: #{cron_jobs.size}"
      puts "cron jobs configured: #{configured_jobs.size}"
    rescue StandardError => e
      abort("Redis/Sidekiq check failed: #{e.class}: #{e.message}")
    end
  end

  desc "Abort if more than one Sidekiq worker is running (development helper)"
  task assert_single_worker: :environment do
    require "sidekiq/api"

    processes = Sidekiq::ProcessSet.new.to_a

    if processes.size > 1
      abort("Multiple Sidekiq workers are running:\n#{process_lines(processes).join("\n")}")
    end

    puts "Single Sidekiq worker check passed"
  end

  desc "List loaded Sidekiq cron jobs"
  task cron: :environment do
    require "sidekiq/cron/job"

    configured_jobs = configured_cron_jobs
    loaded_jobs = Sidekiq::Cron::Job.all.sort_by(&:name)

    if configured_jobs.empty?
      puts "No cron jobs configured for #{Rails.env}"
    else
      puts "Configured cron jobs (#{configured_jobs.size}) for #{Rails.env}:"
      configured_jobs.each do |name, config|
        puts "#{name}: #{config["cron"]} (#{config["class"]})"
      end
    end

    puts "Loaded cron jobs in Redis (#{loaded_jobs.size}):"
    loaded_jobs.each do |job|
      puts "#{job.name}: #{job.cron} (#{job.klass})"
    end
  end

  desc "Clear Sidekiq queue/retry/dead/scheduled sets (development only)"
  task clear_dev: :environment do
    abort("queue:clear_dev is restricted to development") unless Rails.env.development?

    require "sidekiq/api"

    Sidekiq::Queue.all.each(&:clear)
    Sidekiq::RetrySet.new.clear
    Sidekiq::DeadSet.new.clear
    Sidekiq::ScheduledSet.new.clear

    puts "Cleared Sidekiq queue state for development"
  end
end
