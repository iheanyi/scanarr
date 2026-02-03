class LibraryController < ApplicationController
  def index
    @series = Series.includes(:cover_attachment, :chapters, :sources)
                    .order(canonical_title: :asc)

    # Filter by status
    case params[:status]
    when "downloaded"
      @series = @series.select { |s| s.download_progress[:downloaded] > 0 && s.download_progress[:downloaded] == s.download_progress[:total] }
    when "in_progress"
      @series = @series.select { |s| s.download_progress[:downloading] > 0 || (s.download_progress[:downloaded] > 0 && s.download_progress[:downloaded] < s.download_progress[:total]) }
    when "not_downloaded"
      @series = @series.select { |s| s.download_progress[:downloaded] == 0 && s.download_progress[:downloading] == 0 }
    end

    # Search by title
    if params[:q].present?
      query = params[:q].downcase
      @series = @series.select { |s| s.canonical_title.downcase.include?(query) || s.localized_title&.downcase&.include?(query) }
    end

    # Convert to array if still a relation (for non-filtered case)
    @series = @series.to_a if @series.respond_to?(:to_a) && !@series.is_a?(Array)

    # Stats
    @total_series = Series.count
    @total_chapters = Chapter.count
    @downloaded_chapters = FileAsset.where(download_status: "complete").count
  end
end
