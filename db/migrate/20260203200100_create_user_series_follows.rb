class CreateUserSeriesFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :user_series_follows do |t|
      t.references :user, null: false, foreign_key: true
      t.references :library_series, null: false, foreign_key: true
      t.integer :download_policy, default: 0, null: false
      t.jsonb :source_priority, default: []

      t.datetime :created_at, null: false
    end

    add_index :user_series_follows, [:user_id, :library_series_id], unique: true
  end
end
