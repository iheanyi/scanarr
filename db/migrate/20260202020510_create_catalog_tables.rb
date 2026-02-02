class CreateCatalogTables < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :key, null: false
      t.string :name
      t.string :source_type
      t.string :base_url
      t.string :api_version
      t.jsonb :capabilities
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
    add_index :sources, :key, unique: true

    create_table :series do |t|
      t.string :canonical_title, null: false
      t.string :status
      t.string :series_type
      t.string :language_policy
      t.string :metadata_source_id
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :series, :canonical_title
    add_index :series, :deleted_at

    create_table :series_sources do |t|
      t.references :series, null: false, foreign_key: true
      t.references :source, null: false, foreign_key: true
      t.string :source_series_id
      t.datetime :last_checked_at

      t.timestamps
    end
    add_index :series_sources, [ :series_id, :source_id ], unique: true

    create_table :volumes do |t|
      t.references :series, null: false, foreign_key: true
      t.string :volume_number
      t.string :title
      t.date :release_date

      t.timestamps
    end
    add_index :volumes, [ :series_id, :volume_number ], unique: true

    create_table :chapters do |t|
      t.references :series, null: false, foreign_key: true
      t.references :volume, foreign_key: true
      t.string :chapter_number, null: false
      t.string :title
      t.string :language
      t.string :group
      t.references :source, foreign_key: true
      t.datetime :published_at
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :chapters, [ :series_id, :chapter_number, :language, :group ], unique: true
    add_index :chapters, [ :series_id, :chapter_number ]

    create_table :releases do |t|
      t.references :chapter, null: false, foreign_key: true
      t.references :source, foreign_key: true
      t.string :quality
      t.string :format
      t.bigint :filesize
      t.string :checksum
      t.datetime :published_at
      t.datetime :deleted_at
      t.string :source_url

      t.timestamps
    end
    add_index :releases, [ :source_id, :published_at ]
    add_index :releases, :deleted_at

    create_table :file_assets do |t|
      t.references :release, null: false, foreign_key: true
      t.string :path
      t.string :format
      t.integer :page_count
      t.string :checksum
      t.string :storage_id

      t.timestamps
    end
    add_index :file_assets, [ :release_id, :checksum ]
  end
end
