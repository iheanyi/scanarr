class CreateScraperRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :scraper_runs do |t|
      t.references :source, null: false, foreign_key: true
      t.string :run_type, null: false
      t.string :status, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.text :error
      t.jsonb :stats_json

      t.timestamps
    end

    add_index :scraper_runs, [ :source_id, :created_at ]
    add_index :scraper_runs, :status
  end
end
