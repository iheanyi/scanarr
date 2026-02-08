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

      # Sort options for following view
      @sort_by = params[:sort_by].presence || "recently_updated"
      case @sort_by
      when "alphabetical"
        base_scope = base_scope.order(canonical_title: :asc)
      when "most_unread"
        # Sort by unread count descending; falls back to alphabetical for ties
        unread_subquery = NewChapterNotification.unread
          .where(user: current_user)
          .joins(chapter: :series)
          .where(series: { library_series_id: followed_library_series_ids })
          .group("series.library_series_id")
          .select("series.library_series_id AS ls_id, COUNT(*) AS unread_count")

        base_scope = base_scope
          .joins("LEFT JOIN (#{unread_subquery.to_sql}) AS unread_counts ON unread_counts.ls_id = series.library_series_id")
          .order(Arel.sql("COALESCE(unread_counts.unread_count, 0) DESC, series.canonical_title ASC"))
      else # recently_updated
        base_scope = base_scope
          .left_joins(:series_sources)
          .order(Arel.sql("MAX(series_sources.last_checked_at) DESC NULLS LAST"))
          .group("series.id")
      end

      @series = base_scope.page(params[:page]).per(30)

      # Pre-compute unread counts per library_series_id
      @unread_counts = NewChapterNotification.unread
        .where(user: current_user)
        .joins(chapter: :series)
        .where(series: { library_series_id: followed_library_series_ids })
        .group("series.library_series_id")
        .count

      # Pre-compute last checked timestamps per series_id
      series_ids = @series.map(&:id)
      @last_checked = SeriesSource
        .where(series_id: series_ids)
        .group(:series_id)
        .maximum(:last_checked_at)
    elsif params[:status].present?
      # Status filtering via SQL subqueries (avoids loading all series into memory)
      case params[:status]
      when "downloaded"
        downloaded_ids = FileAsset.where(download_status: "complete")
                                  .joins(release: { chapter: :series })
                                  .select("series.id")
                                  .distinct
        base_scope = base_scope.where(id: downloaded_ids)
      when "in_progress"
        in_progress_ids = FileAsset.where(download_status: %w[downloading queued pending])
                                   .joins(release: { chapter: :series })
                                   .select("series.id")
                                   .distinct
        base_scope = base_scope.where(id: in_progress_ids)
      when "not_downloaded"
        any_download_ids = FileAsset.where(download_status: %w[complete downloading queued pending])
                                    .joins(release: { chapter: :series })
                                    .select("series.id")
                                    .distinct
        base_scope = base_scope.where.not(id: any_download_ids)
      end

      @series = base_scope.page(params[:page]).per(30)
    else
      # No status filter: paginate at the DB level (much faster)
      @series = base_scope.page(params[:page]).per(30)
    end

    # Pre-compute download progress for displayed series only
    preload_download_progress(@series)

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
