# frozen_string_literal: true

class FollowsController < ApplicationController
  # Authentication handled by ApplicationController
  before_action :set_library_series, only: [ :create ]
  before_action :set_follow, only: [ :update, :destroy ]

  def create
    @follow = current_user.user_series_follows.build(
      library_series: @library_series,
      download_policy: params[:download_policy] || :notify_only
    )

    if @follow.save
      @series = @library_series.series.first
      respond_to do |format|
        format.html { redirect_back fallback_location: library_path, notice: "Now following #{@library_series.canonical_title}" }
        format.turbo_stream { render turbo_stream: follow_turbo_streams(notice: "Now following #{@library_series.canonical_title}") }
      end
    else
      redirect_back fallback_location: library_path, alert: "Could not follow series"
    end
  end

  def update
    if @follow.update(follow_params)
      @series = @follow.library_series.series.first
      notice = update_notice
      respond_to do |format|
        format.html { redirect_back fallback_location: library_path, notice: notice }
        format.turbo_stream { render turbo_stream: follow_turbo_streams(notice: notice) }
      end
    else
      redirect_back fallback_location: library_path, alert: "Could not update settings"
    end
  end

  def destroy
    title = @follow.library_series.canonical_title
    @series = @follow.library_series.series.first
    @follow.destroy

    respond_to do |format|
      format.html { redirect_back fallback_location: library_path, notice: "Unfollowed #{title}" }
      format.turbo_stream { render turbo_stream: follow_turbo_streams(notice: "Unfollowed #{title}") }
    end
  end

  private

  def set_library_series
    @library_series = LibrarySeries.find(params[:library_series_id])
  end

  def set_follow
    @follow = current_user.user_series_follows.find(params[:id])
  end

  def follow_params
    params.require(:user_series_follow).permit(:download_policy, :check_interval_minutes, source_priority: [])
  end

  def update_notice
    if params.dig(:user_series_follow, :check_interval_minutes)
      interval = @follow.check_interval_minutes
      label = UserSeriesFollow::INTERVAL_OPTIONS.find { |_, v| v == interval }&.first || "Default"
      "Check frequency updated to #{label}"
    elsif @follow.download_policy == "auto_download"
      "Auto-download enabled"
    else
      "Auto-download disabled"
    end
  end

  def follow_turbo_streams(notice: nil)
    user_follow = @follow&.persisted? ? @follow : nil
    streams = []
    streams << turbo_stream.replace("follow-controls",
      UI::FollowControlsComponent.new(series: @series, user_follow: user_follow))
    streams << turbo_stream.append("toast-container",
      UI::ToastComponent.new(message: notice, variant: :success)) if notice.present?
    streams
  end
end
