# frozen_string_literal: true

# Recomputes every source's health from passive signals (smoke-run history,
# per-series check failures). Makes no network requests, so it is safe to run
# frequently. Active probing stays a manual admin action.
class SourceHealthSweepJob < ApplicationJob
  queue_as :default

  def perform
    Source.find_each do |source|
      Sources::HealthEvaluator.new(source).call
    rescue StandardError => e
      Rails.logger.error "[SourceHealthSweepJob] #{source.key}: #{e.message}"
    end
  end
end
