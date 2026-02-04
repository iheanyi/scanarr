# frozen_string_literal: true

class CheckSourceForChaptersJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 3, key: ->(series_id, _, _) { "check_chapters:#{series_id}" }

  def perform(series_id, follow_id, source_id = nil)
    series = Series.find_by(id: series_id)
    follow = UserSeriesFollow.find_by(id: follow_id)
    source = source_id ? Source.find_by(id: source_id) : series&.primary_source

    return unless series && follow && source

    adapter = AdapterRegistry.for(source)
    series_source = series.series_sources.find_by(source: source)
    source_series_id = series_source&.source_series_id

    return unless source_series_id

    chapters_data = adapter.chapters(source_series_id)

    new_chapter_count = 0
    chapters_data.each do |ch_data|
      next if series.chapters.exists?(chapter_number: ch_data.number, language: ch_data.language || "en")

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

      if follow.auto_download? && chapter.source_url.present?
        DownloadChapterJob.perform_later(
          chapter.source_url,
          source_key: source.key,
          series_title: series.canonical_title,
          source_series_id: series_source&.source_series_id,
          chapter_number: chapter.chapter_number,
          chapter_title: chapter.title,
          language: chapter.language,
          group: chapter.group
        )
      end

      new_chapter_count += 1
    end

    Rails.logger.info "[CheckSourceForChaptersJob] Found #{new_chapter_count} new chapters for series #{series_id}"
  rescue StandardError => e
    Rails.logger.error "[CheckSourceForChaptersJob] Error checking series #{series_id}: #{e.message}"
  end
end
