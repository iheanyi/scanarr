# frozen_string_literal: true

# Extended performance audit - second pass
#
# Additional indexes identified from deep query analysis:
#
# 1. series: author_name - OR query in series_importer.rb
# 2. series: artist_name - OR query in series_importer.rb
# 3. series_sources: [source_id, source_series_id] - find_by lookup
# 4. sources: name - ORDER BY name queries
# 5. scraper_runs: run_type - filtering and distinct queries
# 6. chapters: [series_id, source_id, chapter_number] - precise chapter lookup
# 7. chapters: language - filtering by language
# 8. chapters: published_at - ordering by publish date
# 9. releases: [source_id, source_url] - source URL lookups
# 10. new_chapter_notifications: [user_id, created_at] - notification ordering
#
class AddRemainingPerformanceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # ========================================
    # SERIES TABLE
    # ========================================

    # Index for author/artist matching in series deduplication
    # Used in: SeriesImporter - OR query on author_name/artist_name
    # Query: Series.where(canonical_title: X).where("author_name = ? OR artist_name = ?", name, name)
    add_index :series, :author_name,
              name: "index_series_on_author_name",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :series, :artist_name,
              name: "index_series_on_artist_name",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # SERIES_SOURCES TABLE
    # ========================================

    # Compound index for source + source_series_id lookup
    # Used in: SeriesImporter, DownloadChapterJob
    # Query: SeriesSource.find_by(source: X, source_series_id: Y)
    add_index :series_sources, [ :source_id, :source_series_id ],
              name: "index_series_sources_on_source_id_and_source_series_id",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # SOURCES TABLE
    # ========================================

    # Index for name ordering (used in multiple controllers)
    # Used in: SearchController, CalendarController, SourcesController
    # Query: Source.order(:name)
    add_index :sources, :name,
              name: "index_sources_on_name",
              algorithm: :concurrently,
              if_not_exists: true

    # Compound index for enabled + name (sorted filtered queries)
    # Query: Source.where(enabled: true).order(:name, :key)
    add_index :sources, [ :enabled, :name ],
              name: "index_sources_on_enabled_and_name",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # SCRAPER_RUNS TABLE
    # ========================================

    # Index for run_type filtering and distinct queries
    # Used in: Admin::ScrapersController
    # Query: ScraperRun.where(run_type: X), ScraperRun.distinct.pluck(:run_type)
    add_index :scraper_runs, :run_type,
              name: "index_scraper_runs_on_run_type",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # CHAPTERS TABLE
    # ========================================

    # Triple compound for precise chapter lookup by number within series/source
    # Used in: ChaptersController#load_context
    # Query: chapter_scope.find_by(chapter_number: X) where scope is series+source
    add_index :chapters, [ :series_id, :source_id, :chapter_number ],
              name: "index_chapters_on_series_source_chapter_number",
              algorithm: :concurrently,
              if_not_exists: true

    # Index for language filtering (common filter parameter)
    add_index :chapters, :language,
              name: "index_chapters_on_language",
              algorithm: :concurrently,
              if_not_exists: true

    # Index for published_at ordering (release date sorting)
    add_index :chapters, :published_at,
              name: "index_chapters_on_published_at",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # NEW_CHAPTER_NOTIFICATIONS TABLE
    # ========================================

    # Compound for user notification listing with created_at ordering
    # Query: current_user.new_chapter_notifications.order(created_at: :desc)
    add_index :new_chapter_notifications, [ :user_id, :created_at ],
              name: "index_new_chapter_notifications_on_user_id_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # FILE_ASSETS TABLE
    # ========================================

    # Compound for storage lookups
    add_index :file_assets, :storage_id,
              name: "index_file_assets_on_storage_id",
              algorithm: :concurrently,
              if_not_exists: true

    # ========================================
    # LIBRARY_SERIES TABLE
    # ========================================

    # Index for status filtering (if used)
    add_index :library_series, :status,
              name: "index_library_series_on_status",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
