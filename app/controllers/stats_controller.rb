class StatsController < ApplicationController
  def show
    @total_chapters_read = current_user.chapter_progresses.where(status: "completed").count
    @series_with_progress = current_user.chapter_progresses.select(:chapter_id)
                                        .joins(:chapter)
                                        .distinct("chapters.series_id")
                                        .count("DISTINCT chapters.series_id")
    @total_pages_read = current_user.chapter_progresses.where(status: "completed").sum(:page_count)
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
    # Get the most recent progressed_at for each series
    recent_series = current_user.chapter_progresses
                                .joins(:chapter)
                                .group("chapters.series_id")
                                .order(Arel.sql("MAX(chapter_progresses.progressed_at) DESC"))
                                .limit(10)
                                .pluck("chapters.series_id")

    return Series.none if recent_series.empty?

    # Preserve the recency order using PostgreSQL array_position
    Series.where(id: recent_series)
          .includes(:cover_attachment, :sources)
          .order(Arel.sql("array_position(ARRAY[#{recent_series.join(',')}], series.id)"))
  end
end
