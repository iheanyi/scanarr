class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # High priority indexes for common queries

    # releases.created_at - used for ordering (.order(created_at: :desc))
    add_index :releases, :created_at

    # file_assets.updated_at - used in admin downloads (.order(updated_at: :desc))
    add_index :file_assets, :updated_at

    # series_sources.source_series_id - used for lookups by external ID
    add_index :series_sources, :source_series_id

    # Composite index for file_assets status + updated_at queries
    add_index :file_assets, [ :download_status, :updated_at ],
              name: "index_file_assets_on_status_and_updated_at"

    # Index for finding chapters by source URL
    add_index :chapters, :source_url, where: "source_url IS NOT NULL"

    # Index for releases by source URL
    add_index :releases, :source_url, where: "source_url IS NOT NULL"
  end
end
