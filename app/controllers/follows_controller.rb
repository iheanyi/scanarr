# frozen_string_literal: true

class FollowsController < ApplicationController
  # Authentication handled by ApplicationController
  before_action :set_library_series, only: [:create]
  before_action :set_follow, only: [:update, :destroy]

  def create
    @follow = current_user.user_series_follows.build(
      library_series: @library_series,
      download_policy: params[:download_policy] || :notify_only
    )

    if @follow.save
      respond_to do |format|
        format.html { redirect_back fallback_location: library_index_path, notice: "Now following #{@library_series.canonical_title}" }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: library_index_path, alert: "Could not follow series"
    end
  end

  def update
    if @follow.update(follow_params)
      respond_to do |format|
        format.html { redirect_back fallback_location: library_index_path, notice: "Follow settings updated" }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: library_index_path, alert: "Could not update settings"
    end
  end

  def destroy
    title = @follow.library_series.canonical_title
    @follow.destroy

    respond_to do |format|
      format.html { redirect_back fallback_location: library_index_path, notice: "Unfollowed #{title}" }
      format.turbo_stream
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
    params.require(:user_series_follow).permit(:download_policy, source_priority: [])
  end
end
