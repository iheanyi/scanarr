class LibraryController < ApplicationController
  include GenreFiltering

  STATUS_OPTIONS = [
    [ "All", "" ],
    [ "Downloaded", "downloaded" ],
    [ "In Progress", "in_progress" ],
    [ "Not Started", "not_started" ],
    [ "Completed", "completed" ],
    [ "Following", "following" ]
  ].freeze

  SORT_OPTIONS = {
    "alphabetical" => "A–Z",
    "reverse_alpha" => "Z–A",
    "recently_added" => "Recently Added",
    "chapter_count" => "Most Chapters"
  }.freeze

  FOLLOWING_SORT_OPTIONS = {
    "recently_updated" => "Recently Updated",
    "alphabetical" => "A–Z",
    "reverse_alpha" => "Z–A",
    "most_unread" => "Most Unread",
    "chapter_count" => "Most Chapters"
  }.freeze

  def index
    @status = normalized_status_param
    @source_ids = normalized_source_ids
    @genres = normalized_genres
    @status_options = STATUS_OPTIONS
    @source_options = Source.joins(:series_sources).distinct.order(:name, :key).map do |source|
      [ source.display_name_with_content_rating, source.id.to_s ]
    end
    @genre_options = available_genre_options

    base_scope = Series.includes({ cover_attachment: :blob }, :sources, :series_sources)

    # Search by title (SQL)
    base_scope = apply_search_filter(base_scope)
    base_scope = apply_source_filter(base_scope)
    base_scope = apply_genre_filter(base_scope)

    # "Following" filter: only show series the user is following
    if @status == "following"
      followed_library_series_ids = current_user.user_series_follows.pluck(:library_series_id)
      @followed_library_series_ids = Set.new(followed_library_series_ids)
      base_scope = base_scope.where(library_series_id: followed_library_series_ids)

      # Sort options for following view
      @sort_by = params[:sort_by].presence || "recently_updated"
      @sort_options = FOLLOWING_SORT_OPTIONS
      case @sort_by
      when "alphabetical"
        base_scope = base_scope.order(canonical_title: :asc)
      when "reverse_alpha"
        base_scope = base_scope.order(canonical_title: :desc)
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
      when "chapter_count"
        base_scope = base_scope.order(chapters_count: :desc, canonical_title: :asc)
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
    elsif @status.present?
      # Status filtering via SQL subqueries (avoids loading all series into memory)
      base_scope = apply_status_filter(base_scope, @status)

      @sort_by = params[:sort_by].presence || "alphabetical"
      @sort_options = SORT_OPTIONS
      base_scope = apply_sort(base_scope, @sort_by)
      @series = base_scope.page(params[:page]).per(30)
    else
      # No status filter
      @sort_by = params[:sort_by].presence || "alphabetical"
      @sort_options = SORT_OPTIONS
      base_scope = apply_sort(base_scope, @sort_by)
      @series = base_scope.page(params[:page]).per(30)
    end

    # Pre-compute download progress for displayed series only
    preload_download_progress(@series)

    # Pre-load follow data for library cards (reuse if already computed by "following" filter)
    unless defined?(@followed_library_series_ids) && @followed_library_series_ids
      if current_user
        followed_ids = current_user.user_series_follows.pluck(:library_series_id)
        @followed_library_series_ids = Set.new(followed_ids)
      else
        @followed_library_series_ids = Set.new
      end
    end

    # Stats — single query instead of 3 separate COUNT queries
    stats = ActiveRecord::Base.connection.select_one(<<~SQL)
      SELECT
        (SELECT COUNT(*) FROM series) AS total_series,
        (SELECT COUNT(*) FROM chapters) AS total_chapters,
        (SELECT COUNT(*) FROM file_assets WHERE download_status = 'complete') AS downloaded_chapters
    SQL
    @total_series = stats["total_series"]
    @total_chapters = stats["total_chapters"]
    @downloaded_chapters = stats["downloaded_chapters"]
  end

  def random
    status = normalized_status_param
    source_ids = normalized_source_ids
    genres = normalized_genres
    scope = Series.includes(:sources, :series_sources)
    scope = apply_search_filter(scope)
    scope = apply_source_filter(scope, source_ids)
    scope = apply_genre_filter(scope, genres)
    scope = apply_status_filter(scope, status) if status.present?

    selected = scope.reorder(Arel.sql("RANDOM()")).first
    if selected
      redirect_to library_series_path(series_slug: selected.to_param)
    else
      redirect_to library_path(
        status: status.presence,
        q: params[:q],
        sort_by: params[:sort_by],
        source_ids: source_ids.presence,
        genres: genres.presence
      ),
                  alert: "No series found for current filters"
    end
  end

  private

  def normalized_status_param
    status = params[:status].to_s
    return "not_started" if status == "not_downloaded"

    valid = STATUS_OPTIONS.map { |(_, value)| value }.reject(&:blank?)
    valid.include?(status) ? status : ""
  end

  def normalized_source_ids
    ids = Array(params[:source_ids]).map { |value| value.to_s.strip }
    ids.select! { |value| value.match?(/\A\d+\z/) }
    ids.uniq!
    return [] if ids.empty?

    allowed_ids = Source.where(id: ids.map(&:to_i)).pluck(:id).map(&:to_s)
    ids & allowed_ids
  end

  def apply_search_filter(scope)
    return scope unless params[:q].present?

    query = "%#{params[:q]}%"
    scope.where(
      "LOWER(canonical_title) LIKE LOWER(:q) OR LOWER(localized_title) LIKE LOWER(:q)",
      q: query
    )
  end

  def apply_source_filter(scope, source_ids = @source_ids)
    return scope if source_ids.blank?

    source_series_ids = SeriesSource.where(source_id: source_ids).select(:series_id)
    scope.where(id: source_series_ids)
  end

  def apply_genre_filter(scope, genres = @genres)
    return scope if genres.blank?

    category_column = Series.arel_table[:normalized_categories]
    predicate = genres
      .map { |genre| Arel::Nodes::InfixOperation.new("?", category_column, Arel::Nodes.build_quoted(genre)) }
      .reduce { |left, right| Arel::Nodes::Or.new(left, right) }

    scope.where(predicate)
  end

  def apply_status_filter(scope, status)
    case status
    when "downloaded"
      downloaded_ids = FileAsset.where(download_status: "complete")
                                .joins(release: { chapter: :series })
                                .select("series.id")
                                .distinct
      scope.where(id: downloaded_ids)
    when "in_progress"
      in_progress_ids = FileAsset.where(download_status: %w[downloading queued pending])
                                 .joins(release: { chapter: :series })
                                 .select("series.id")
                                 .distinct
      scope.where(id: in_progress_ids)
    when "not_started"
      return scope unless current_user

      started_series_ids = ChapterProgress.where(user: current_user)
                                          .joins(chapter: :series)
                                          .select("series.id")
                                          .distinct
      scope.where.not(id: started_series_ids)
    when "completed"
      return scope.none unless current_user

      completed_series_ids = ChapterProgress.where(user: current_user, status: "completed")
                                            .joins(chapter: :series)
                                            .select("series.id")
                                            .distinct
      scope.where(id: completed_series_ids)
    when "following"
      return scope.none unless current_user

      followed_ids = current_user.user_series_follows.select(:library_series_id)
      scope.where(library_series_id: followed_ids)
    else
      scope
    end
  end

  def apply_sort(scope, sort_by)
    case sort_by
    when "reverse_alpha"
      scope.order(canonical_title: :desc)
    when "recently_added"
      scope.order(created_at: :desc)
    when "chapter_count"
      scope.order(chapters_count: :desc, canonical_title: :asc)
    else # alphabetical
      scope.order(canonical_title: :asc)
    end
  end

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
