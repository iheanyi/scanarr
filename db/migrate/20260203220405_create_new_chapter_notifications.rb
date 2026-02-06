# frozen_string_literal: true

class CreateNewChapterNotifications < ActiveRecord::Migration[8.0]
  def change
    unless table_exists?(:new_chapter_notifications)
      create_table :new_chapter_notifications do |t|
        t.references :user, null: false, foreign_key: true
        t.references :chapter, null: false, foreign_key: true
        t.boolean :read, default: false
        t.timestamp :created_at
      end

      add_index :new_chapter_notifications, [ :user_id, :read, :created_at ], name: "idx_notifications_user_read_created"
    end
  end
end
