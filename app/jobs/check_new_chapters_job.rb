# frozen_string_literal: true

class CheckNewChaptersJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "check_new_chapters"

  # Stagger window: spread enqueued jobs across this many seconds
  STAGGER_WINDOW_SECONDS = 300

  # Sources with this many consecutive failures get admin notifications
  NEEDS_ATTENTION_THRESHOLD = 3

  def perform
    follows = UserSeriesFollow.includes(library_series: { series: [ series_sources: :source ] })
    count = follows.count

    Rails.logger.info "[CheckNewChaptersJob] Starting check for #{count} follows"

    enqueued = 0
    skipped_interval = 0
    skipped_rate_limit = 0
    skipped_stale = 0

    follows.find_each do |follow|
      follow.library_series.series.each do |series|
        series.series_sources.each do |ss|
          next unless ss.source_series_id.present?

          # Skip stale sources (10+ consecutive failures)
          if ss.stale?
            skipped_stale += 1
            next
          end

          # Skip if the source is rate-limited
          if ss.source.rate_limited?
            skipped_rate_limit += 1
            next
          end

          # Skip if we checked recently enough for this follow's interval
          unless follow.needs_check?(ss)
            skipped_interval += 1
            next
          end

          # Stagger jobs across the stagger window to avoid thundering herd
          delay_seconds = series.id % STAGGER_WINDOW_SECONDS
          CheckSourceForChaptersJob.set(wait: delay_seconds.seconds)
            .perform_later(series.id, follow.id, ss.source_id)

          enqueued += 1
        end
      end
    end

    # Notify admins about sources that need attention
    notify_admins_about_unhealthy_sources

    Rails.logger.info "[CheckNewChaptersJob] Enqueued #{enqueued} checks " \
      "(skipped #{skipped_interval} interval, #{skipped_rate_limit} rate-limited, " \
      "#{skipped_stale} stale) for #{count} follows"
  end

  private

  def notify_admins_about_unhealthy_sources
    unhealthy = SeriesSource.needs_attention.includes(:source).group_by(&:source)
    return if unhealthy.empty?

    admin_users = User.where(role: :admin)
    return if admin_users.none?

    unhealthy.each do |source, series_sources|
      message = "Source #{source.name} has #{series_sources.size} series with " \
                "#{NEEDS_ATTENTION_THRESHOLD}+ consecutive failures"

      admin_users.find_each do |admin|
        # Only create one notification per source per day
        existing = admin.new_chapter_notifications
          .where("created_at > ?", 1.day.ago)
          .joins(:chapter)
          .where(chapters: { source: source })
          .exists?

        next if existing

        Rails.logger.warn "[CheckNewChaptersJob] #{message}"
      end
    end
  end
end
