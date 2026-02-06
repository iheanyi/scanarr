class UserSeriesFollow < ApplicationRecord
  belongs_to :user
  belongs_to :library_series

  enum :download_policy, { notify_only: 0, auto_download: 1 }

  validates :user_id, uniqueness: { scope: :library_series_id }
  validates :check_interval_minutes, inclusion: { in: [ nil, 15, 30, 60, 360, 720, 1440 ] }

  INTERVAL_OPTIONS = [
    [ "Use default (30 min)", nil ],
    [ "Every 15 minutes", 15 ],
    [ "Every 30 minutes", 30 ],
    [ "Every hour", 60 ],
    [ "Every 6 hours", 360 ],
    [ "Every 12 hours", 720 ],
    [ "Daily", 1440 ]
  ].freeze

  DEFAULT_INTERVAL_MINUTES = 30

  # Helper method to check if auto-download is enabled
  def auto_download?
    download_policy == "auto_download"
  end

  # Returns the effective check interval, falling back to the default
  def effective_interval_minutes
    check_interval_minutes || DEFAULT_INTERVAL_MINUTES
  end

  # Check whether a series_source is due for a check based on this follow's interval
  def needs_check?(series_source)
    return true if series_source.last_checked_at.nil?
    series_source.last_checked_at < effective_interval_minutes.minutes.ago
  end

  # Returns the preferred source for downloads based on source_priority
  # Falls back to the given default source if no priority is set
  def preferred_source_for(chapter, default_source)
    return default_source if source_priority.blank?

    series = chapter.series
    available_sources = series.series_sources.includes(:source).map(&:source)

    # Find the highest-priority source that is available for this series
    source_priority.each do |source_key|
      preferred = available_sources.find { |s| s.key == source_key }
      return preferred if preferred
    end

    default_source
  end
end
