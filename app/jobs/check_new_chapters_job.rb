# frozen_string_literal: true

class CheckNewChaptersJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "check_new_chapters"

  # Stagger window: spread enqueued jobs across this many seconds
  STAGGER_WINDOW_SECONDS = 300

  def perform
    follows = UserSeriesFollow.includes(library_series: { series: [ series_sources: :source ] })
    count = follows.count

    Rails.logger.info "[CheckNewChaptersJob] Starting check for #{count} follows"

    enqueued = 0
    skipped_interval = 0
    skipped_rate_limit = 0

    follows.find_each do |follow|
      follow.library_series.series.each do |series|
        series.series_sources.each do |ss|
          next unless ss.source_series_id.present?

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

    Rails.logger.info "[CheckNewChaptersJob] Enqueued #{enqueued} checks " \
      "(skipped #{skipped_interval} interval, #{skipped_rate_limit} rate-limited) " \
      "for #{count} follows"
  end
end
