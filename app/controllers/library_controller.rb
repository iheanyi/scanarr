class LibraryController < ApplicationController
  def index
    base_scope = Series.includes(:cover_attachment, :sources, :series_sources)
                       .order(canonical_title: :asc)

    # Search by title (SQL)
    if params[:q].present?
      query = "%#{params[:q]}%"
      base_scope = base_scope.where(
        "LOWER(canonical_title) LIKE LOWER(:q) OR LOWER(localized_title) LIKE LOWER(:q)",
        q: query
      )
    end

    # "Following" filter: only show series the user is following
    if params[:status] == "following"
      followed_library_series_ids = current_user.user_series_follows.pluck(:library_series_id)
      base_scope = base_scope.where(library_series_id: followed_library_series_ids)
      @series = base_scope.page(params[:page]).per(30)
    elsif params[:status].present?
      # Status filtering requires download progress data
      # Load with full association chain for status filtering
      all_series = base_scope.includes(chapters: { releases: :file_asset }).to_a

      case params[:status]
      when "downloaded"
        all_series = all_series.select do |s|
          progress = s.download_progress
          progress[:downloaded] > 0 && progress[:downloaded] == progress[:total]
        end
      when "in_progress"
        all_series = all_series.select do |s|
          progress = s.download_progress
          progress[:downloading] > 0 || (progress[:downloaded] > 0 && progress[:downloaded] < progress[:total])
        end
      when "not_downloaded"
        all_series = all_series.select do |s|
          progress = s.download_progress
          progress[:downloaded] == 0 && progress[:downloading] == 0
        end
      end

      @series = Kaminari.paginate_array(all_series).page(params[:page]).per(30)
    else
      # No status filter: paginate at the DB level (much faster)
      @series = base_scope.page(params[:page]).per(30)
    end

    # Pre-compute download progress for displayed series only
    # (skip for download-status filters that already loaded the full tree)
    unless params[:status].in?(%w[downloaded in_progress not_downloaded])
      preload_download_progress(@series)
    end

    # Pre-load follow data for library cards
    if current_user
      followed_ids = current_user.user_series_follows.pluck(:library_series_id)
      @followed_library_series_ids = Set.new(followed_ids)
    else
      @followed_library_series_ids = Set.new
    end

    # Stats (single queries, no N+1)
    @total_series = Series.count
    @total_chapters = Chapter.count
    @downloaded_chapters = FileAsset.where(download_status: "complete").count
  end

  private

  # Batch-load download progress for a page of series using SQL aggregation
  # instead of loading the entire chapters/releases/file_assets tree
  def preload_download_progress(series_collection)
    series_ids = series_collection.map(&:id)
    return if series_ids.empty?

    stats = Chapter.where(series_id: series_ids)
                   .left_joins(releases: :file_asset)
                   .group(:series_id)
                   .select(
                     "chapters.series_id",
                     "COUNT(DISTINCT chapters.id) AS total",
                     "COUNT(DISTINCT CASE WHEN file_assets.download_status = 'complete' THEN chapters.id END) AS downloaded",
                     "COUNT(DISTINCT CASE WHEN file_assets.download_status IN ('downloading', 'queued', 'pending') THEN chapters.id END) AS downloading"
                   )
                   .index_by(&:series_id)

    series_collection.each do |s|
      row = stats[s.id]
      s.instance_variable_set(:@download_progress, {
        total: row&.total.to_i,
        downloaded: row&.downloaded.to_i,
        downloading: row&.downloading.to_i,
        queued: 0,
        failed: 0
      })
    end
  end
end
