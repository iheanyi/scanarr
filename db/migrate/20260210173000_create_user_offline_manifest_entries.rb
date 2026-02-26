class CreateUserOfflineManifestEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :user_offline_manifest_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :chapter, null: false, foreign_key: true
      t.string :status, null: false, default: "pinned"
      t.datetime :last_synced_at
      t.datetime :completed_at
      t.text :last_error

      t.timestamps
    end

    add_index :user_offline_manifest_entries, [ :user_id, :chapter_id ], unique: true, name: "index_offline_manifest_on_user_and_chapter"
    add_index :user_offline_manifest_entries, [ :user_id, :status ], name: "index_offline_manifest_on_user_and_status"
    add_index :user_offline_manifest_entries, :updated_at
  end
end
