# frozen_string_literal: true

class CheckSourceForChaptersJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 3, key: ->(series_id, _follow_id, _source_id) { "check_chapters:#{series_id}" }

  # Patterns indicating a rate limit response from the source
  RATE_LIMIT_PATTERNS = [ "429", "rate limit", "too many requests", "throttle" ].freeze

  def perform(series_id, follow_id, source_id = nil)
    series = Series.find_by(id: series_id)
    follow = UserSeriesFollow.find_by(id: follow_id)
    source = source_id ? Source.find_by(id: source_id) : series&.primary_source

    return unless series && follow && source

    # Double-check at execution time (state may have changed since enqueue).
    # Broken/dead sources are skipped entirely; the health sweep's recheck
    # probe is the only scheduled traffic they receive.
    return if !source.enabled? || source.rate_limited? || source.broken? || source.dead?

    adapter = Scrapers::AdapterRegistry.for(source)
    series_source = series.series_sources.find_by(source: source)
    source_series_id = series_source&.source_series_id

    return unless source_series_id

    chapters_data = adapter.chapters(source_series_id)

    # Keep chapter identity (and reading progress) stable across providers, while
    # recording each provider's acquisition URL on its own release.
    existing_chapters = series.chapters.includes(releases: :file_asset)
      .index_by { |chapter| [ chapter.chapter_number, chapter.language || "en" ] }
    new_chapters = []
    download_candidates = []

    chapters_data.each do |ch_data|
      key = [ ch_data.number.to_s, ch_data.language || "en" ]
      chapter = existing_chapters[key]

      unless chapter
        chapter = series.chapters.create!(
          chapter_number: ch_data.number,
          title: ch_data.title,
          language: key.last,
          group: ch_data.group,
          source: source,
          source_url: ch_data.url,
          published_at: ch_data.published_at
        )
        existing_chapters[key] = chapter
        NewChapterNotification.create!(user: follow.user, chapter: chapter)
        new_chapters << chapter
      end

      next if ch_data.url.blank?

      release = chapter.releases.find { |candidate| candidate.source_id == source.id }
      if release
        release.update!(source_url: ch_data.url) if release.source_url != ch_data.url
      else
        release = chapter.releases.create!(source: source, source_url: ch_data.url, format: "pages")
      end

      # A previously discovered release may become preferred after replacement
      # or switching from notify-only. Fill that gap, but leave failed assets
      # for explicit retry and preserve saved/active downloads from any source.
      needs_download = release.file_asset.nil? && chapter.releases.none? do |candidate|
        candidate.file_asset&.download_status.in?(%w[complete queued pending downloading])
      end
      download_candidates << release if needs_download
    end
    download_candidates.uniq!(&:id)

    if follow.auto_download? && download_candidates.any? && preferred_download_source_key(follow, series, source) == source.key
      enqueue_downloads(download_candidates, series, source, series_source)
    end

    series_source&.record_check_success!

    # Clear rate limit on successful check (source is healthy)
    source.clear_rate_limit! if source.rate_limited_until.present?

    # Broadcast notification updates if new chapters were found
    if new_chapters.any?
      broadcast_notification_update(follow.user)
    end

    Rails.logger.info "[CheckSourceForChaptersJob] Found #{new_chapters.size} new chapters for series #{series_id}"
  rescue StandardError => e
    # Detect rate limiting from error messages and back off
    if rate_limit_error?(e)
      source&.record_rate_limit!(5.minutes)
      Rails.logger.warn "[CheckSourceForChaptersJob] Rate limited by source #{source&.key}, backing off 5 minutes"
    end

    series_source&.record_check_failure!(e.message)
    Rails.logger.error "[CheckSourceForChaptersJob] Error checking series #{series_id}: #{e.message}"

    # Re-derive health on the failure path so a newly broken source stops
    # receiving scheduled traffic now instead of after the next hourly sweep.
    # Success paths stay evaluation-free; failures are the rare case.
    begin
      Sources::HealthEvaluator.new(source).call if source
    rescue StandardError => health_error
      Rails.logger.error "[CheckSourceForChaptersJob] health evaluate #{source&.key}: #{health_error.message}"
    end
  end

  private

  def rate_limit_error?(error)
    message = error.message.downcase
    RATE_LIMIT_PATTERNS.any? { |pattern| message.include?(pattern) }
  end

  def preferred_download_source_key(follow, series, fallback_source)
    return fallback_source.key if follow.source_priority.blank?

    eligible_keys = series.series_sources.includes(:source).filter_map do |mapping|
      candidate = mapping.source
      next if mapping.source_series_id.blank? || mapping.stale?
      next unless candidate.enabled?
      next if candidate.broken? || candidate.dead? || candidate.rate_limited?

      candidate.key
    end.to_set

    follow.source_priority.find { |key| eligible_keys.include?(key) } || fallback_source.key
  end

  def enqueue_downloads(releases, series, source, series_source)
    releases.each do |release|
      chapter = release.chapter

      # A provider key must always travel with that provider's URL and series
      # identifier. Substituting a preferred key here sends incompatible URLs
      # to another adapter. The release also pins the existing chapter identity.
      DownloadChapterJob.perform_later(
        release.source_url,
        source_key: source.key,
        series_title: series.canonical_title,
        source_series_id: series_source.source_series_id,
        chapter_number: chapter.chapter_number,
        chapter_title: chapter.title,
        language: chapter.language,
        group: chapter.group,
        release_id: release.id
      )
    end
  end

  def broadcast_notification_update(user)
    unread_count = user.new_chapter_notifications.unread.count
    display = unread_count > 9 ? "9+" : unread_count.to_s

    badge_classes = if unread_count > 0
      "ml-auto inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-accent text-[10px] font-semibold text-accent-foreground"
    else
      "ml-auto inline-flex h-4 min-w-4 items-center justify-center rounded-full"
    end

    html = %(<span data-notification-count="true" class="#{badge_classes}">#{unread_count > 0 ? display : ""}</span>)

    Turbo::StreamsChannel.broadcast_replace_to(
      [ user, :notifications ],
      targets: "[data-notification-count]",
      html: html
    )
  end
end
