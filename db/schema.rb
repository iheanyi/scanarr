# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_11_000100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "backup_records", force: :cascade do |t|
    t.string "backup_type", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "filename", null: false
    t.string "path"
    t.bigint "size"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_type"], name: "index_backup_records_on_backup_type"
    t.index ["created_at"], name: "index_backup_records_on_created_at"
    t.index ["status"], name: "index_backup_records_on_status"
  end

  create_table "chapter_progresses", force: :cascade do |t|
    t.bigint "chapter_id", null: false
    t.datetime "created_at", null: false
    t.integer "page_count", null: false
    t.integer "page_index", null: false
    t.datetime "progressed_at", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["chapter_id"], name: "index_chapter_progresses_on_chapter_id"
    t.index ["user_id", "chapter_id"], name: "index_chapter_progresses_on_user_id_and_chapter_id", unique: true
    t.index ["user_id", "status"], name: "index_chapter_progresses_on_user_id_and_status"
    t.index ["user_id"], name: "index_chapter_progresses_on_user_id"
  end

  create_table "chapters", force: :cascade do |t|
    t.string "chapter_number", null: false
    t.decimal "chapter_number_value", precision: 12, scale: 3
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "group"
    t.string "language"
    t.string "public_id", null: false
    t.datetime "published_at"
    t.bigint "series_id", null: false
    t.bigint "source_id"
    t.string "source_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "volume_id"
    t.index ["language"], name: "index_chapters_on_language"
    t.index ["public_id"], name: "index_chapters_on_public_id", unique: true
    t.index ["published_at"], name: "index_chapters_on_published_at"
    t.index ["series_id", "chapter_number", "language", "group"], name: "idx_on_series_id_chapter_number_language_group_a553be271a", unique: true
    t.index ["series_id", "chapter_number"], name: "index_chapters_on_series_id_and_chapter_number"
    t.index ["series_id", "created_at"], name: "index_chapters_on_series_id_and_created_at"
    t.index ["series_id", "source_id", "chapter_number"], name: "index_chapters_on_series_source_chapter_number"
    t.index ["series_id", "source_id", "chapter_number_value"], name: "index_chapters_on_series_source_number_value"
    t.index ["series_id", "source_id"], name: "index_chapters_on_series_id_and_source_id"
    t.index ["series_id"], name: "index_chapters_on_series_id"
    t.index ["source_id", "source_url"], name: "index_chapters_on_source_id_and_source_url"
    t.index ["source_id"], name: "index_chapters_on_source_id"
    t.index ["source_url"], name: "index_chapters_on_source_url"
    t.index ["volume_id"], name: "index_chapters_on_volume_id"
  end

  create_table "file_assets", force: :cascade do |t|
    t.string "checksum"
    t.datetime "created_at", null: false
    t.text "download_error"
    t.string "download_status", default: "pending", null: false
    t.string "format"
    t.integer "page_count"
    t.integer "pages_downloaded", default: 0, null: false
    t.integer "pages_expected"
    t.string "path"
    t.string "public_id", null: false
    t.bigint "release_id", null: false
    t.string "storage_id"
    t.datetime "updated_at", null: false
    t.index ["download_status", "updated_at"], name: "index_file_assets_on_status_and_updated_at"
    t.index ["download_status"], name: "index_file_assets_on_download_status"
    t.index ["public_id"], name: "index_file_assets_on_public_id", unique: true
    t.index ["release_id", "checksum"], name: "index_file_assets_on_release_id_and_checksum"
    t.index ["release_id"], name: "index_file_assets_on_release_id"
    t.index ["storage_id"], name: "index_file_assets_on_storage_id"
    t.index ["updated_at"], name: "index_file_assets_on_updated_at"
  end

  create_table "library_series", force: :cascade do |t|
    t.integer "anilist_id"
    t.string "canonical_title", null: false
    t.string "cover_url"
    t.datetime "created_at", null: false
    t.integer "mal_id"
    t.uuid "mangadex_id"
    t.string "public_id", null: false
    t.string "slug", null: false
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["anilist_id"], name: "index_library_series_on_anilist_id"
    t.index ["canonical_title"], name: "index_library_series_on_canonical_title"
    t.index ["mal_id"], name: "index_library_series_on_mal_id"
    t.index ["mangadex_id"], name: "index_library_series_on_mangadex_id"
    t.index ["public_id"], name: "index_library_series_on_public_id", unique: true
    t.index ["slug"], name: "index_library_series_on_slug", unique: true
    t.index ["status"], name: "index_library_series_on_status"
  end

  create_table "new_chapter_notifications", force: :cascade do |t|
    t.bigint "chapter_id", null: false
    t.datetime "created_at", null: false
    t.boolean "read", default: false, null: false
    t.bigint "user_id", null: false
    t.index ["chapter_id"], name: "index_new_chapter_notifications_on_chapter_id"
    t.index ["user_id", "created_at"], name: "index_new_chapter_notifications_on_user_id_and_created_at"
    t.index ["user_id", "read", "created_at"], name: "index_new_chapter_notifications_user_read_created"
    t.index ["user_id"], name: "index_new_chapter_notifications_on_user_id"
  end

  create_table "pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "file_asset_id", null: false
    t.integer "position", null: false
    t.string "source_url"
    t.datetime "updated_at", null: false
    t.index ["file_asset_id", "position"], name: "index_pages_on_file_asset_id_and_position", unique: true
    t.index ["file_asset_id"], name: "index_pages_on_file_asset_id"
  end

  create_table "releases", force: :cascade do |t|
    t.bigint "chapter_id", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "filesize"
    t.string "format"
    t.string "public_id", null: false
    t.datetime "published_at"
    t.string "quality"
    t.bigint "source_id"
    t.string "source_url"
    t.datetime "updated_at", null: false
    t.index ["chapter_id", "source_id", "created_at"], name: "index_releases_on_chapter_source_created"
    t.index ["chapter_id", "source_id"], name: "index_releases_on_chapter_id_and_source_id"
    t.index ["chapter_id"], name: "index_releases_on_chapter_id"
    t.index ["created_at"], name: "index_releases_on_created_at"
    t.index ["deleted_at"], name: "index_releases_on_deleted_at"
    t.index ["public_id"], name: "index_releases_on_public_id", unique: true
    t.index ["source_id", "published_at"], name: "index_releases_on_source_id_and_published_at"
    t.index ["source_id"], name: "index_releases_on_source_id"
    t.index ["source_url"], name: "index_releases_on_source_url"
  end

  create_table "scraper_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.string "run_type", null: false
    t.bigint "source_id", null: false
    t.datetime "started_at", null: false
    t.jsonb "stats_json"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["run_type"], name: "index_scraper_runs_on_run_type"
    t.index ["source_id", "created_at"], name: "index_scraper_runs_on_source_id_and_created_at"
    t.index ["source_id", "status", "created_at"], name: "index_scraper_runs_on_source_status_created"
    t.index ["source_id"], name: "index_scraper_runs_on_source_id"
    t.index ["status"], name: "index_scraper_runs_on_status"
  end

  create_table "series", force: :cascade do |t|
    t.json "alt_titles", default: []
    t.string "artist_name"
    t.string "author_name"
    t.string "canonical_title", null: false
    t.integer "chapters_count", default: 0, null: false
    t.string "cover_url"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "language_policy"
    t.bigint "library_series_id"
    t.string "localized_title"
    t.string "metadata_source_id"
    t.jsonb "normalized_categories", default: [], null: false
    t.string "public_id", null: false
    t.decimal "quality_score", precision: 8, scale: 2
    t.jsonb "raw_tags", default: [], null: false
    t.string "reading_style"
    t.string "series_type"
    t.string "slug", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.index "lower((canonical_title)::text) gin_trgm_ops", name: "index_series_on_lower_canonical_title_trgm", using: :gin
    t.index "lower((localized_title)::text) gin_trgm_ops", name: "index_series_on_lower_localized_title_trgm", where: "(localized_title IS NOT NULL)", using: :gin
    t.index ["artist_name"], name: "index_series_on_artist_name"
    t.index ["author_name"], name: "index_series_on_author_name"
    t.index ["canonical_title"], name: "index_series_on_canonical_title"
    t.index ["deleted_at"], name: "index_series_on_deleted_at"
    t.index ["library_series_id"], name: "index_series_on_library_series_id"
    t.index ["normalized_categories"], name: "index_series_on_normalized_categories_gin", using: :gin
    t.index ["public_id"], name: "index_series_on_public_id", unique: true
    t.index ["reading_style"], name: "index_series_on_reading_style"
    t.index ["slug"], name: "index_series_on_slug", unique: true
    t.index ["status"], name: "index_series_on_status"
  end

  create_table "series_sources", force: :cascade do |t|
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "last_check_error"
    t.datetime "last_check_error_at"
    t.datetime "last_checked_at"
    t.string "library_base_path"
    t.bigint "series_id", null: false
    t.bigint "source_id", null: false
    t.string "source_series_id"
    t.datetime "updated_at", null: false
    t.index ["series_id", "last_checked_at"], name: "index_series_sources_on_series_id_and_last_checked_at"
    t.index ["series_id", "source_id"], name: "index_series_sources_on_series_id_and_source_id", unique: true
    t.index ["series_id"], name: "index_series_sources_on_series_id"
    t.index ["source_id", "source_series_id"], name: "index_series_sources_on_source_id_and_source_series_id"
    t.index ["source_id"], name: "index_series_sources_on_source_id"
    t.index ["source_series_id"], name: "index_series_sources_on_source_series_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "site_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "registration_enabled", default: true, null: false
    t.datetime "updated_at", null: false
  end

  create_table "sources", force: :cascade do |t|
    t.integer "adapter_version", default: 0, null: false
    t.datetime "adapter_version_synced_at"
    t.string "base_url"
    t.jsonb "capabilities"
    t.datetime "created_at", null: false
    t.integer "default_priority", default: 50, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "health_changed_at"
    t.string "health_status", default: "healthy", null: false
    t.string "key", null: false
    t.string "name"
    t.datetime "rate_limited_until"
    t.string "slug", null: false
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["enabled", "name"], name: "index_sources_on_enabled_and_name"
    t.index ["enabled"], name: "index_sources_on_enabled"
    t.index ["health_status"], name: "index_sources_on_health_status"
    t.index ["key"], name: "index_sources_on_key", unique: true
    t.index ["name"], name: "index_sources_on_name"
    t.index ["slug"], name: "index_sources_on_slug", unique: true
  end

  create_table "user_offline_manifest_entries", force: :cascade do |t|
    t.bigint "chapter_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.string "status", default: "pinned", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["chapter_id"], name: "index_user_offline_manifest_entries_on_chapter_id"
    t.index ["updated_at"], name: "index_user_offline_manifest_entries_on_updated_at"
    t.index ["user_id", "chapter_id"], name: "index_offline_manifest_on_user_and_chapter", unique: true
    t.index ["user_id", "status"], name: "index_offline_manifest_on_user_and_status"
    t.index ["user_id"], name: "index_user_offline_manifest_entries_on_user_id"
  end

  create_table "user_series_follows", force: :cascade do |t|
    t.integer "check_interval_minutes"
    t.datetime "created_at", null: false
    t.integer "download_policy", default: 0, null: false
    t.bigint "library_series_id", null: false
    t.jsonb "source_priority", default: []
    t.bigint "user_id", null: false
    t.index ["download_policy"], name: "index_user_series_follows_on_download_policy"
    t.index ["library_series_id"], name: "index_user_series_follows_on_library_series_id"
    t.index ["user_id", "library_series_id"], name: "index_user_series_follows_on_user_id_and_library_series_id", unique: true
    t.index ["user_id"], name: "index_user_series_follows_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "api_key"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "password_digest"
    t.jsonb "preferences", default: {}, null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["api_key"], name: "index_users_on_api_key", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "volumes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "release_date"
    t.bigint "series_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "volume_number"
    t.index ["series_id", "volume_number"], name: "index_volumes_on_series_id_and_volume_number", unique: true
    t.index ["series_id"], name: "index_volumes_on_series_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chapter_progresses", "chapters"
  add_foreign_key "chapter_progresses", "users"
  add_foreign_key "chapters", "series"
  add_foreign_key "chapters", "sources"
  add_foreign_key "chapters", "volumes"
  add_foreign_key "file_assets", "releases"
  add_foreign_key "new_chapter_notifications", "chapters"
  add_foreign_key "new_chapter_notifications", "users"
  add_foreign_key "pages", "file_assets"
  add_foreign_key "releases", "chapters"
  add_foreign_key "releases", "sources"
  add_foreign_key "scraper_runs", "sources"
  add_foreign_key "series", "library_series"
  add_foreign_key "series_sources", "series"
  add_foreign_key "series_sources", "sources"
  add_foreign_key "sessions", "users"
  add_foreign_key "user_offline_manifest_entries", "chapters"
  add_foreign_key "user_offline_manifest_entries", "users"
  add_foreign_key "user_series_follows", "library_series"
  add_foreign_key "user_series_follows", "users"
  add_foreign_key "volumes", "series"
end
