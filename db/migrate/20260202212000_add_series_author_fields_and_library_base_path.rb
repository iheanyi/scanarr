class AddSeriesAuthorFieldsAndLibraryBasePath < ActiveRecord::Migration[8.1]
  def change
    add_column :series, :author_name, :string
    add_column :series, :artist_name, :string
    add_column :series_sources, :library_base_path, :string
  end
end
