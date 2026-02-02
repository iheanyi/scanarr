class CreateDownloadedChapters < ActiveRecord::Migration[8.1]
  def change
    create_table :downloaded_chapters do |t|
      t.string :source_key, null: false
      t.string :chapter_id, null: false
      t.string :chapter_url, null: false

      t.timestamps
    end

    add_index :downloaded_chapters, [ :source_key, :chapter_id ], unique: true
  end
end
