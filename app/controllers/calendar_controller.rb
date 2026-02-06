# frozen_string_literal: true

class CalendarController < ApplicationController
  def index
    @view_type = params[:view].presence || "week"
    @source_filter = params[:source].presence

    # Get followed library series IDs
    followed_library_series_ids = current_user.user_series_follows.pluck(:library_series_id)

    # Get all series linked to followed library series
    followed_series_ids = Series.where(library_series_id: followed_library_series_ids).pluck(:id)

    # Date range based on view type
    case @view_type
    when "week"
      @start_date = Date.current.beginning_of_week
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

    # Query chapters
    chapters_scope = Chapter.includes(:source, series: :cover_attachment)
      .where(series_id: followed_series_ids)
      .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
      .order(created_at: :desc)

    # Apply source filter
    if @source_filter.present?
      source = Source.find_by(slug: @source_filter)
      chapters_scope = chapters_scope.where(source: source) if source
    end

    @chapters_by_date = chapters_scope.group_by { |ch| ch.created_at.to_date }
    @sources = Source.order(:name)
  end
end
