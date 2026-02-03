# frozen_string_literal: true

class CheckNewChaptersJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "check_new_chapters"

  def perform
    follows = UserSeriesFollow.includes(library_series: :series)
    count = follows.count

    Rails.logger.info "[CheckNewChaptersJob] Starting check for #{count} follows"

    follows.find_each do |follow|
      follow.library_series.series.each do |series|
        next unless series.source

        CheckSourceForChaptersJob.perform_later(series.id, follow.id)
      end
    end

    Rails.logger.info "[CheckNewChaptersJob] Enqueued chapter checks for #{count} follows"
  end
end
