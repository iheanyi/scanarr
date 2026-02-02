class AddPublicIdsAndSlugs < ActiveRecord::Migration[8.1]
  def change
    add_column :series, :public_id, :string, null: false
    add_column :series, :slug, :string, null: false
    add_column :chapters, :public_id, :string, null: false
    add_column :releases, :public_id, :string, null: false
    add_column :file_assets, :public_id, :string, null: false

    add_index :series, :public_id, unique: true
    add_index :series, :slug, unique: true
    add_index :chapters, :public_id, unique: true
    add_index :releases, :public_id, unique: true
    add_index :file_assets, :public_id, unique: true
  end
end
