class CreateChapterProgresses < ActiveRecord::Migration[8.1]
  def change
    create_table :chapter_progresses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :chapter, null: false, foreign_key: true
      t.integer :page_index, null: false
      t.integer :page_count, null: false
      t.string :status, null: false
      t.datetime :progressed_at, null: false

      t.timestamps
    end

    add_index :chapter_progresses, %i[user_id chapter_id], unique: true
  end
end
