class AddSourceUrlToChapters < ActiveRecord::Migration[8.1]
  def change
    add_column :chapters, :source_url, :string
    add_index :chapters, [ :source_id, :source_url ]
  end
end
