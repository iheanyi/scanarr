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

    # Double-check rate limit at execution time (may have been set since enqueue)
    return if source.rate_limited?

    adapter = Scrapers::AdapterRegistry.for(source)
    series_source = series.series_sources.find_by(source: source)
    source_series_id = series_source&.source_series_id

    return unless source_series_id

    chapters_data = adapter.chapters(source_series_id)

    # Prefetch existing chapter identifiers to avoid per-chapter EXISTS queries (N+1)
    existing_chapters = series.chapters
      .pluck(:chapter_number, :language)
      .map { |num, lang| [ num, lang ] }
      .to_set

    # Collect new chapters first, then batch notifications and downloads
    new_chapters = []

    chapters_data.each do |ch_data|
      next if existing_chapters.include?([ ch_data.number, ch_data.language || "en" ])

      chapter = series.chapters.create!(
        chapter_number: ch_data.number,
        title: ch_data.title,
        language: ch_data.language || "en",
        group: ch_data.group,
        source: source,
        source_url: ch_data.url,
        published_at: ch_data.published_at
      )

      NewChapterNotification.create!(
        user: follow.user,
        chapter: chapter
      )

      new_chapters << chapter
    end

    # Batch auto-download: enqueue all new chapters after creation is complete
    if follow.auto_download? && new_chapters.any?
      enqueue_downloads(new_chapters, follow, source, series_source)
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
  end

  private

  def rate_limit_error?(error)
    message = error.message.downcase
    RATE_LIMIT_PATTERNS.any? { |pattern| message.include?(pattern) }
  end

  def enqueue_downloads(chapters, follow, source, series_source)
    # All chapters belong to the same series; cache the title to avoid N+1
    series_title = chapters.first&.series&.canonical_title

    chapters.each do |chapter|
      next unless chapter.source_url.present?

      # Use the follow's preferred source if set, otherwise use the discovering source
      download_source = follow.preferred_source_for(chapter, source)

      DownloadChapterJob.perform_later(
        chapter.source_url,
        source_key: download_source.key,
        series_title: series_title,
        source_series_id: series_source&.source_series_id,
        chapter_number: chapter.chapter_number,
        chapter_title: chapter.title,
        language: chapter.language,
        group: chapter.group
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

    html = %(<span id="notification-count" class="#{badge_classes}">#{unread_count > 0 ? display : ""}</span>)

    Turbo::StreamsChannel.broadcast_replace_to(
      [ user, :notifications ],
      target: "notification-count",
      html: html
    )
  end
end
