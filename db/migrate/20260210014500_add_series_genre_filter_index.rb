class AddSeriesGenreFilterIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :series, :normalized_categories,
              using: :gin,
              algorithm: :concurrently,
              name: "index_series_on_normalized_categories_gin",
              if_not_exists: true
  end

  def down
    remove_index :series, name: "index_series_on_normalized_categories_gin", if_exists: true
  end
end
