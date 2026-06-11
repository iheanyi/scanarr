class CreateUpstreamSources < ActiveRecord::Migration[8.1]
  def change
    create_table :upstream_sources do |t|
      t.string :mihon_id, null: false
      t.string :name, null: false
      t.string :lang, null: false
      t.string :base_url
      t.boolean :nsfw, default: false, null: false
      t.string :extension_pkg
      t.integer :extension_version_code
      t.datetime :last_seen_at, null: false
      t.timestamps

      t.index :mihon_id, unique: true
      t.index :lang
      t.index :name
    end

    add_column :sources, :adopted_base_url, :string
  end
end
