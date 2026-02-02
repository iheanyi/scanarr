class AddSeriesMetadataFields < ActiveRecord::Migration[8.1]
  def change
    add_column :series, :reading_style, :string
    add_column :series, :raw_tags, :jsonb, default: [], null: false
    add_column :series, :normalized_categories, :jsonb, default: [], null: false
    add_index :series, :reading_style
  end
end
