# frozen_string_literal: true

class CalendarController < ApplicationController
  def index
    @view_type = params[:view].presence || "week"
    @source_filter = params[:source].presence
    @week_offset = params[:week_offset].to_i

    # Get followed library series IDs
    followed_library_series_ids = current_user.user_series_follows.pluck(:library_series_id)

    # Get all series linked to followed library series
    followed_series_ids = Series.where(library_series_id: followed_library_series_ids).pluck(:id)

    # Date range based on view type
    case @view_type
    when "week"
      @start_date = Date.current.beginning_of_week + @week_offset.weeks
      @end_date = @start_date + 6.days
    when "month"
      @start_date = Date.current.beginning_of_month
      @end_date = Date.current.end_of_month
    when "recent"
      @start_date = 7.days.ago.to_date
      @end_date = Date.current
    else
      @start_date = Date.current.beginning_of_week
      @end_date = @start_date + 6.days
    end

    # Query chapters — use published_at (actual release date), fall back to created_at
    date_range = @start_date.beginning_of_day..@end_date.end_of_day
    chapters_scope = Chapter.includes(:source, series: [ :cover_attachment, :sources, :series_sources ], releases: :file_asset)
      .where(series_id: followed_series_ids)
      .where("COALESCE(chapters.published_at, chapters.created_at) BETWEEN ? AND ?", date_range.first, date_range.last)
      .order(Arel.sql("COALESCE(chapters.published_at, chapters.created_at) DESC"))

    # Apply source filter
    if @source_filter.present?
      source = Source.find_by(slug: @source_filter)
      chapters_scope = chapters_scope.where(source: source) if source
    end

    @chapters_by_date = chapters_scope.group_by { |ch| (ch.published_at || ch.created_at).to_date }
    @sources = Source.order(:name)

    # Preload download status and notification status for calendar chapters
    all_chapter_ids = @chapters_by_date.values.flatten.map(&:id)
    if all_chapter_ids.any?
      @downloaded_chapter_ids = Set.new(
        Release.joins(:file_asset)
          .where(chapter_id: all_chapter_ids)
          .where(file_assets: { download_status: "complete" })
          .pluck(:chapter_id)
      )

      @unread_chapter_ids = Set.new(
        NewChapterNotification.unread
          .where(user: current_user, chapter_id: all_chapter_ids)
          .pluck(:chapter_id)
      )
    else
      @downloaded_chapter_ids = Set.new
      @unread_chapter_ids = Set.new
    end

    # Pre-compute latest release per chapter to avoid N+1 in view
    @latest_release_map = {}
    @chapters_by_date.each_value do |chapters|
      chapters.each do |chapter|
        @latest_release_map[chapter.id] = chapter.releases.to_a.max_by(&:created_at)
      end
    end
  end
end
