class StatsController < ApplicationController
  def show
    @total_chapters_read = current_user.chapter_progresses.where(status: "completed").count
    @series_with_progress = current_user.chapter_progresses.select(:chapter_id)
                                        .joins(:chapter)
                                        .distinct("chapters.series_id")
                                        .count("DISTINCT chapters.series_id")
    @series_followed = current_user.user_series_follows.count
    @chapters_per_week = chapters_per_week_avg

    @daily_activity = daily_reading_activity
    @top_tags = top_tags
    @recently_read = recently_read_series
  end

  private

  def chapters_per_week_avg
    eight_weeks_ago = 8.weeks.ago
    count = current_user.chapter_progresses
                        .where(status: "completed")
                        .where("progressed_at >= ?", eight_weeks_ago)
                        .count
    (count / 8.0).round(1)
  end

  def daily_reading_activity
    twelve_weeks_ago = 12.weeks.ago.to_date
    current_user.chapter_progresses
                .where("progressed_at >= ?", twelve_weeks_ago)
                .group("DATE(progressed_at)")
                .count
  end

  def top_tags
    series_ids = current_user.chapter_progresses
                             .joins(:chapter)
                             .distinct
                             .pluck("chapters.series_id")

    return {} if series_ids.empty?

    Series.where(id: series_ids)
          .pluck(:raw_tags)
          .flatten
          .compact
          .tally
          .sort_by { |_, count| -count }
          .first(10)
          .to_h
  end

  def recently_read_series
    chapter_ids = current_user.chapter_progresses
                              .order(progressed_at: :desc)
                              .limit(100)
                              .pluck(:chapter_id)

    return Series.none if chapter_ids.empty?

    series_ids = Chapter.where(id: chapter_ids)
                        .distinct
                        .pluck(:series_id)

    Series.where(id: series_ids)
          .includes(:cover_attachment, :sources)
          .limit(10)
  end
end
