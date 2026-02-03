class LibraryController < ApplicationController
  def index
    # Eager load full chain to avoid N+1 queries
    @series = Series.includes(
      :cover_attachment,
      :sources,
      :series_sources,
      chapters: { releases: :file_asset }
    ).order(canonical_title: :asc)

    # Search by title (SQL)
    if params[:q].present?
      query = "%#{params[:q]}%"
      @series = @series.where(
        "LOWER(canonical_title) LIKE LOWER(:q) OR LOWER(localized_title) LIKE LOWER(:q)",
        q: query
      )
    end

    # Load into memory for status filtering (uses preloaded data)
    @series = @series.to_a

    # Filter by status using preloaded associations
    case params[:status]
    when "downloaded"
      @series = @series.select do |s|
        progress = s.download_progress
        progress[:downloaded] > 0 && progress[:downloaded] == progress[:total]
      end
    when "in_progress"
      @series = @series.select do |s|
        progress = s.download_progress
        progress[:downloading] > 0 || (progress[:downloaded] > 0 && progress[:downloaded] < progress[:total])
      end
    when "not_downloaded"
      @series = @series.select do |s|
        progress = s.download_progress
        progress[:downloaded] == 0 && progress[:downloading] == 0
      end
    end

    # Stats (single queries, no N+1)
    @total_series = Series.count
    @total_chapters = Chapter.count
    @downloaded_chapters = FileAsset.where(download_status: "complete").count
  end
end
