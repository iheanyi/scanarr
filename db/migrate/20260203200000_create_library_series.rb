class CreateLibrarySeries < ActiveRecord::Migration[8.1]
  def change
    create_table :library_series do |t|
      t.string :public_id, null: false
      t.string :canonical_title, null: false
      t.string :slug, null: false
      t.integer :anilist_id
      t.integer :mal_id
      t.uuid :mangadex_id
      t.string :cover_url
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :library_series, :public_id, unique: true
    add_index :library_series, :slug, unique: true
    add_index :library_series, :anilist_id
    add_index :library_series, :mal_id
    add_index :library_series, :mangadex_id
  end
end
