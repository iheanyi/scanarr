class AddLibraryFilterPerformanceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :series, "LOWER(canonical_title) gin_trgm_ops",
              using: :gin,
              algorithm: :concurrently,
              name: "index_series_on_lower_canonical_title_trgm",
              if_not_exists: true

    add_index :series, "LOWER(localized_title) gin_trgm_ops",
              using: :gin,
              algorithm: :concurrently,
              where: "localized_title IS NOT NULL",
              name: "index_series_on_lower_localized_title_trgm",
              if_not_exists: true

    add_index :chapter_progresses, %i[user_id status],
              algorithm: :concurrently,
              name: "index_chapter_progresses_on_user_id_and_status",
              if_not_exists: true

    add_index :series_sources, %i[series_id last_checked_at],
              algorithm: :concurrently,
              name: "index_series_sources_on_series_id_and_last_checked_at",
              if_not_exists: true
  end

  def down
    remove_index :series, name: "index_series_on_lower_canonical_title_trgm", if_exists: true
    remove_index :series, name: "index_series_on_lower_localized_title_trgm", if_exists: true
    remove_index :chapter_progresses, name: "index_chapter_progresses_on_user_id_and_status", if_exists: true
    remove_index :series_sources, name: "index_series_sources_on_series_id_and_last_checked_at", if_exists: true
  end
end
