# frozen_string_literal: true

# Performance audit identified these missing indexes:
#
# 1. chapters: [series_id, source_id] - filtering chapters by series AND source
# 2. chapters: [series_id, created_at] - calendar queries by date range
# 3. chapters: source_url full index (was partial) - user preference for full indexes
# 4. releases: [chapter_id, source_id] - filtering releases by chapter AND source
# 5. releases: source_url full index (was partial) - user preference for full indexes
# 6. sources: enabled - Search controller filters by enabled: true
# 7. library_series: canonical_title - find_or_create_by! on title
# 8. chapters: [series_id, chapter_number_value] - ordering queries
# 9. file_assets: release_id with chapter join optimization
#
class AddMissingIndexesForPerformance < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # ========================================
    # CHAPTERS TABLE
    # ========================================

    # Compound index for filtering chapters by series AND source
    # Used in: SeriesController#show, ChaptersController#load_context
    # Query: @series.chapters.where(source: @source)
    add_index :chapters, [ :series_id, :source_id ],
              name: "index_chapters_on_series_id_and_source_id",
              algorithm: :concurrently,
              if_not_exists: true

    # Compound index for calendar queries filtering by series and date range
    # Used in: CalendarController#index
    # Query: Chapter.where(series_id: ids).where(created_at: range)
    add_index :chapters, [ :series_id, :created_at ],
              name: "index_chapters_on_series_id_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true

    # Convert partial source_url index to full index
    # User preference: full indexes over partial
    remove_index :chapters, :source_url,
                 name: "index_chapters_on_source_url",
                 if_exists: true

    add_index :chapters, :source_url,
              name: "index_chapters_on_source_url",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # RELEASES TABLE
    # ========================================

    # Compound index for filtering releases by chapter AND source
    # Used in: ChaptersController#latest_release
    # Query: @chapter.releases.where(source: @source).order(created_at: :desc)
    add_index :releases, [ :chapter_id, :source_id ],
              name: "index_releases_on_chapter_id_and_source_id",
              algorithm: :concurrently,
              if_not_exists: true

    # Compound index for ordering releases by source and creation time
    # Used in: filtering releases by source with ordering
    add_index :releases, [ :chapter_id, :source_id, :created_at ],
              name: "index_releases_on_chapter_source_created",
              algorithm: :concurrently,
              if_not_exists: true

    # Convert partial source_url index to full index
    # User preference: full indexes over partial
    remove_index :releases, :source_url,
                 name: "index_releases_on_source_url",
                 if_exists: true

    add_index :releases, :source_url,
              name: "index_releases_on_source_url",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # SOURCES TABLE
    # ========================================

    # Index on enabled for filtering active sources
    # Used in: SearchController#index
    # Query: Source.where(enabled: true)
    add_index :sources, :enabled,
              name: "index_sources_on_enabled",
              algorithm: :concurrently,
              if_not_exists: true

    # Index on slug for URL lookups (derived from key but used in queries)
    # Note: slug is computed, but if you add a slug column, index it
    # Currently slug is derived from key which is already indexed

    # ========================================
    # LIBRARY_SERIES TABLE
    # ========================================

    # Index on canonical_title for find_or_create_by lookups
    # Used in: Series#ensure_library_series!
    # Query: LibrarySeries.find_or_create_by!(canonical_title: X)
    add_index :library_series, :canonical_title,
              name: "index_library_series_on_canonical_title",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # SERIES TABLE
    # ========================================

    # Compound index for library page ordering
    # Used in: LibraryController#index
    # Query: Series.order(canonical_title: :asc)
    # Note: Already has single index, but adding for completeness

    # Index for filtering by status (if used in queries)
    add_index :series, :status,
              name: "index_series_on_status",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # FILE_ASSETS TABLE
    # ========================================

    # Index for finding complete downloads (stats queries)
    # Used in: LibraryController#index stats
    # Query: FileAsset.where(download_status: "complete").count
    # Note: Already has download_status index, but compound may help

    # ========================================
    # USER_SERIES_FOLLOWS TABLE
    # ========================================

    # Index on download_policy for filtering by policy type
    add_index :user_series_follows, :download_policy,
              name: "index_user_series_follows_on_download_policy",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # SCRAPER_RUNS TABLE
    # ========================================

    # Compound index for reliability score calculation
    # Used in: Source#reliability_score
    # Query: scraper_runs.where("created_at > ?", 30.days.ago).where(status: X)
    add_index :scraper_runs, [ :source_id, :status, :created_at ],
              name: "index_scraper_runs_on_source_status_created",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
