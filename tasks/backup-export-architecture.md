# Backup & Export Architecture for Scanarr

## Table of Contents

1. [Context & Prior Art](#1-context--prior-art)
2. [Automated Database Backups](#2-automated-database-backups)
3. [Library Export/Import (Portable Format)](#3-library-exportimport-portable-format)
4. [Settings Export/Import](#4-settings-exportimport)
5. [Mihon Compatibility Layer](#5-mihon-compatibility-layer)
6. [Admin UI](#6-admin-ui)
7. [API Endpoints](#7-api-endpoints)
8. [Implementation Plan](#8-implementation-plan)

---

## 1. Context & Prior Art

### System Overview

Scanarr is a self-hosted manga management app built with Rails 8.1. Key infrastructure:

- **Database**: PostgreSQL (primary, cache, queue, cable databases in production)
- **File storage**: Active Storage with local disk service (`storage/` directory)
  - Series covers (`Series#cover` -- `has_one_attached :cover`)
  - Chapter page images (`Page#image` -- `has_one_attached :image`)
  - Chapter archives (`FileAsset#archive` -- `has_one_attached :archive`)
- **Background jobs**: SolidQueue with recurring tasks defined in `config/recurring.yml`
- **Real-time**: Solid Cable for Turbo Streams broadcasts
- **Caching**: Solid Cache

### Data Model Summary

```
User
  has_many :chapter_progresses       # reading progress per chapter
  has_many :user_series_follows      # follow + download policy per library series
  has_many :new_chapter_notifications

LibrarySeries                        # canonical series identity
  has_many :series                   # source-specific series records
  has_many :user_series_follows
  status enum: ongoing/completed/hiatus/cancelled
  anilist_id, mal_id, mangadex_id    # external service IDs

Series                               # per-source series record
  has_many :chapters
  has_many :sources (through :series_sources)
  has_one_attached :cover
  reading_style, language_policy, raw_tags, normalized_categories

Chapter
  belongs_to :series
  has_many :releases                 # one chapter can have multiple releases from different sources
  has_many :chapter_progresses

Release
  belongs_to :chapter
  belongs_to :source
  has_one :file_asset

FileAsset
  has_many :pages
  has_one_attached :archive          # packaged CBZ
  download_status: pending/queued/downloading/complete/failed/cancelled

Source
  key: "mangadex", "weeb_central", etc.
  slug: "mangadex", "weeb-central", etc.
  base_url, capabilities, enabled, default_priority
```

### How Comparable Apps Handle This

#### Sonarr/Radarr

- **Backup format**: ZIP file containing SQLite database (`nzbdrone.db`) + config file (`config.xml`)
- **Scheduling**: Built-in scheduled task, configurable interval (default: every 7 days) and retention count
- **API**: `GET /api/v3/system/backup` to list, `POST` to trigger, download link for each backup
- **Restore**: Stop app, extract ZIP over config directory, restart
- **Limitation**: Does NOT back up PostgreSQL when using PG instead of SQLite; only backs up SQLite
- **What's excluded**: Media files (too large). Only metadata + configuration

#### Kavita

- **Backup format**: ZIP containing SQLite database (`kavita.db`), bookmarks, configuration
- **Location**: `config/backups/` by default
- **Scheduling**: Nightly automated backups
- **Known issue**: Database file sometimes missing from backup if in active use during backup (SQLite locking)
- **Restore**: Stop Kavita, extract backup ZIP into config directory, restart

#### Komga

- **Backup**: No built-in export/import for library data. External `komga-backup` command for database files
- **Feature requests**: Community has asked for reading list JSON export, metadata export, cross-instance sync
- **Current state**: Metadata import from ComicInfo.xml is supported, but no portable library format

#### Mihon (Tachiyomi)

- **Backup format**: `.tachibk` -- Protocol Buffers serialized, then GZipped
- **Schema**: Available via app debug info. Key models:

```protobuf
message Backup {
  repeated BackupManga backupManga = 1;
  repeated BackupCategory backupCategories = 2;
  repeated BackupSource backupSources = 101;
}

message BackupManga {
  int64 source = 1;          // source ID
  string url = 2;            // manga URL on source
  string title = 3;
  string artist = 4;
  string author = 5;
  string description = 6;
  repeated string genre = 7;
  int32 status = 8;
  string thumbnailUrl = 9;
  int64 dateAdded = 13;
  int32 viewer = 14;         // reading mode (RTL, LTR, vertical, webtoon)
  repeated BackupChapter chapters = 16;
  repeated int64 categories = 17;
  repeated BackupTracking tracking = 18;
  bool favorite = 100;
  int32 chapterFlags = 101;
  repeated BackupHistory history = 104;
  int32 updateStrategy = 105;
  repeated string excludedScanlators = 108;
}

message BackupChapter {
  string url = 1;
  string name = 2;
  string scanlator = 3;
  bool read = 4;
  bool bookmark = 5;
  int32 lastPageRead = 6;
  int64 dateFetch = 7;
  int64 dateUpload = 8;
  float chapterNumber = 9;
  int32 sourceOrder = 10;
  int64 lastModifiedAt = 11;
  int64 version = 12;
}
```

- **What's included**: Library entries, chapters, read status, tracking (AniList/MAL/etc.), categories, reading preferences, source info, extension repos, app settings
- **What's excluded**: Downloaded chapter files, extension APKs, custom covers
- **Restore**: Merge or overwrite existing library. User picks strategy per manga (keep newer, overwrite, skip)
- **Automatic backups**: Configurable frequency, stored on device, syncable to cloud via FolderSync

### Design Principles Derived from Prior Art

1. **Separate metadata backup from media backup** -- Every app does this. Media files are too large and can be re-downloaded.
2. **Backups should be self-contained** -- A single file (ZIP or compressed archive) containing everything needed.
3. **API-triggerable** -- Sonarr got this right. Backups should be creatable and downloadable via API.
4. **Retention policies are essential** -- Without them, backups eat all disk space.
5. **Backup before restore** -- Always create a safety backup before importing/restoring anything.
6. **PostgreSQL needs different backup strategy than SQLite** -- Cannot just copy the file. Must use `pg_dump`.

---

## 2. Automated Database Backups

### Strategy

Since Scanarr uses PostgreSQL (not SQLite), we need `pg_dump`-based backups. This is fundamentally different from how Sonarr/Kavita handle it (they copy SQLite files), but gives us more robust options.

### Backup Contents

A full backup ZIP contains:

```
scanarr_backup_2026-02-05_030000.zip
  database.sql.gz          # pg_dump of primary database (gzipped)
  active_storage_blobs.json # blob metadata (keys, filenames, checksums) - NOT the actual files
  manifest.json            # backup metadata
  config/
    sources.yml            # scraper source configuration
    storage.yml            # Active Storage configuration (sanitized)
```

**manifest.json** structure:

```json
{
  "version": 1,
  "format": "scanarr_backup",
  "created_at": "2026-02-05T03:00:00Z",
  "scanarr_version": "0.1.0",
  "rails_version": "8.1.2",
  "database_adapter": "postgresql",
  "database_name": "scanarr_production",
  "checksum": "sha256:abc123...",
  "tables": {
    "series": 150,
    "chapters": 12500,
    "users": 1,
    "user_series_follows": 45
  },
  "active_storage": {
    "total_blobs": 3200,
    "total_bytes": 15432100000
  }
}
```

### Backup Service

```ruby
# app/services/backup/database_backup_service.rb
module Backup
  class DatabaseBackupService
    BACKUP_DIR = Rails.root.join("storage/backups")
    MAX_DUMP_TIME = 300 # 5 minutes

    Result = Data.define(:path, :size, :checksum, :manifest)

    def initialize(destination: BACKUP_DIR, include_config: true)
      @destination = Pathname.new(destination)
      @include_config = include_config
    end

    def perform
      FileUtils.mkdir_p(@destination)

      timestamp = Time.current.strftime("%Y-%m-%d_%H%M%S")
      filename = "scanarr_backup_#{timestamp}.zip"
      zip_path = @destination.join(filename)

      Dir.mktmpdir("scanarr_backup") do |tmpdir|
        tmpdir = Pathname.new(tmpdir)

        # 1. Dump PostgreSQL database
        dump_database(tmpdir.join("database.sql.gz"))

        # 2. Export Active Storage blob metadata (not the files themselves)
        export_blob_metadata(tmpdir.join("active_storage_blobs.json"))

        # 3. Copy configuration files (sanitized)
        if @include_config
          copy_config(tmpdir.join("config"))
        end

        # 4. Generate manifest
        manifest = generate_manifest(tmpdir)
        File.write(tmpdir.join("manifest.json"), JSON.pretty_generate(manifest))

        # 5. Create ZIP archive
        create_zip(tmpdir, zip_path)
      end

      checksum = Digest::SHA256.file(zip_path).hexdigest
      manifest = JSON.parse(File.read(zip_path)) rescue {}

      Result.new(
        path: zip_path,
        size: File.size(zip_path),
        checksum: checksum,
        manifest: manifest
      )
    end

    private

    def dump_database(output_path)
      db_config = ActiveRecord::Base.connection_db_config.configuration_hash

      cmd = [
        "pg_dump",
        "--no-owner",
        "--no-privileges",
        "--clean",
        "--if-exists",
        "--format=plain"
      ]

      cmd += [ "-h", db_config[:host] ] if db_config[:host]
      cmd += [ "-p", db_config[:port].to_s ] if db_config[:port]
      cmd += [ "-U", db_config[:username] ] if db_config[:username]
      cmd << db_config[:database]

      env = {}
      env["PGPASSWORD"] = db_config[:password] if db_config[:password]

      # Pipe through gzip for compression
      IO.popen(env, cmd, err: [ :child, :out ]) do |pg_out|
        Zlib::GzipWriter.open(output_path.to_s) do |gz|
          IO.copy_stream(pg_out, gz)
        end
      end

      unless $?.success?
        raise "pg_dump failed with exit code #{$?.exitstatus}"
      end
    end

    def export_blob_metadata(output_path)
      blobs = ActiveStorage::Blob.all.map do |blob|
        {
          key: blob.key,
          filename: blob.filename.to_s,
          content_type: blob.content_type,
          byte_size: blob.byte_size,
          checksum: blob.checksum,
          service_name: blob.service_name,
          created_at: blob.created_at.iso8601,
          # Include attachment info for mapping back to records
          attachments: blob.attachments.map do |att|
            { record_type: att.record_type, record_id: att.record_id, name: att.name }
          end
        }
      end

      File.write(output_path, JSON.pretty_generate(blobs))
    end

    def copy_config(config_dir)
      FileUtils.mkdir_p(config_dir)

      # Copy sources.yml (scraper configuration)
      sources_path = Rails.root.join("config/sources.yml")
      FileUtils.cp(sources_path, config_dir.join("sources.yml")) if sources_path.exist?

      # Copy storage.yml but sanitize credentials
      storage_path = Rails.root.join("config/storage.yml")
      if storage_path.exist?
        content = File.read(storage_path)
        # Redact any credential-like values
        sanitized = content.gsub(/(?<=secret_access_key:\s).+/, "[REDACTED]")
                           .gsub(/(?<=access_key_id:\s).+/, "[REDACTED]")
        File.write(config_dir.join("storage.yml"), sanitized)
      end
    end

    def generate_manifest(tmpdir)
      table_counts = {}
      %w[series chapters library_series users user_series_follows
         chapter_progresses sources series_sources releases
         file_assets pages volumes].each do |table|
        table_counts[table] = ActiveRecord::Base.connection.execute(
          "SELECT COUNT(*) FROM #{table}"
        ).first["count"]
      end

      {
        version: 1,
        format: "scanarr_backup",
        created_at: Time.current.iso8601,
        scanarr_version: Scanarr::VERSION,
        rails_version: Rails.version,
        database_adapter: "postgresql",
        database_name: ActiveRecord::Base.connection_db_config.database,
        tables: table_counts,
        active_storage: {
          total_blobs: ActiveStorage::Blob.count,
          total_bytes: ActiveStorage::Blob.sum(:byte_size)
        }
      }
    end

    def create_zip(source_dir, zip_path)
      require "zip"

      Zip::File.open(zip_path, create: true) do |zipfile|
        Dir.glob("#{source_dir}/**/*").each do |file|
          next if File.directory?(file)
          entry_name = Pathname.new(file).relative_path_from(source_dir).to_s
          zipfile.add(entry_name, file)
        end
      end
    end
  end
end
```

### Backup Restoration

```ruby
# app/services/backup/database_restore_service.rb
module Backup
  class DatabaseRestoreService
    Result = Data.define(:success, :tables_restored, :errors)

    def initialize(backup_path:, dry_run: false)
      @backup_path = Pathname.new(backup_path)
      @dry_run = dry_run
      @errors = []
    end

    def perform
      validate_backup!

      if @dry_run
        return dry_run_report
      end

      # CRITICAL: Create a safety backup before restoring
      safety_backup = DatabaseBackupService.new(
        destination: Rails.root.join("storage/backups/pre_restore")
      ).perform
      Rails.logger.info "[Restore] Safety backup created at #{safety_backup.path}"

      tables_restored = restore_database
      restore_config

      Result.new(
        success: @errors.empty?,
        tables_restored: tables_restored,
        errors: @errors
      )
    end

    private

    def validate_backup!
      raise "Backup file not found: #{@backup_path}" unless @backup_path.exist?
      raise "Not a ZIP file" unless @backup_path.extname == ".zip"

      Zip::File.open(@backup_path) do |zip|
        raise "Missing manifest.json" unless zip.find_entry("manifest.json")
        raise "Missing database.sql.gz" unless zip.find_entry("database.sql.gz")

        manifest = JSON.parse(zip.read("manifest.json"))
        raise "Unknown backup format" unless manifest["format"] == "scanarr_backup"
        raise "Unsupported backup version: #{manifest['version']}" unless manifest["version"] <= 1
      end
    end

    def dry_run_report
      manifest = nil
      Zip::File.open(@backup_path) do |zip|
        manifest = JSON.parse(zip.read("manifest.json"))
      end

      current_counts = {}
      manifest["tables"].each_key do |table|
        current_counts[table] = ActiveRecord::Base.connection.execute(
          "SELECT COUNT(*) FROM #{table}"
        ).first["count"] rescue 0
      end

      Result.new(
        success: true,
        tables_restored: manifest["tables"].transform_values.with_index { |backup_count, _|
          # Report what would change
          { backup: backup_count, current: current_counts }
        },
        errors: [ "DRY RUN: No changes made" ]
      )
    end

    def restore_database
      Dir.mktmpdir("scanarr_restore") do |tmpdir|
        Zip::File.open(@backup_path) do |zip|
          zip.extract("database.sql.gz", File.join(tmpdir, "database.sql.gz"))
        end

        sql_path = File.join(tmpdir, "database.sql")

        # Decompress
        Zlib::GzipReader.open(File.join(tmpdir, "database.sql.gz")) do |gz|
          File.open(sql_path, "w") { |f| IO.copy_stream(gz, f) }
        end

        # Restore using psql
        db_config = ActiveRecord::Base.connection_db_config.configuration_hash
        cmd = [ "psql" ]
        cmd += [ "-h", db_config[:host] ] if db_config[:host]
        cmd += [ "-p", db_config[:port].to_s ] if db_config[:port]
        cmd += [ "-U", db_config[:username] ] if db_config[:username]
        cmd += [ "-d", db_config[:database] ]
        cmd += [ "-f", sql_path ]

        env = {}
        env["PGPASSWORD"] = db_config[:password] if db_config[:password]

        output, status = Open3.capture2e(env, *cmd)
        unless status.success?
          @errors << "psql restore failed: #{output.last(500)}"
        end
      end
    end

    def restore_config
      Zip::File.open(@backup_path) do |zip|
        # Restore sources.yml if present
        if (entry = zip.find_entry("config/sources.yml"))
          target = Rails.root.join("config/sources.yml")
          # Back up existing before overwriting
          FileUtils.cp(target, "#{target}.bak") if target.exist?
          File.write(target, zip.read(entry))
        end
      end
    end
  end
end
```

### Scheduling with SolidQueue

Add to `config/recurring.yml`:

```yaml
production:
  # ... existing jobs ...

  scheduled_backup:
    class: ScheduledBackupJob
    schedule: at 3am every day
    queue: backups

  backup_retention_cleanup:
    class: BackupRetentionCleanupJob
    schedule: at 4am every day
    queue: backups
```

### Backup Job

```ruby
# app/jobs/scheduled_backup_job.rb
class ScheduledBackupJob < ApplicationJob
  queue_as :backups
  limits_concurrency to: 1, key: "scheduled_backup"

  def perform
    Rails.logger.info "[ScheduledBackupJob] Starting automated backup"

    result = Backup::DatabaseBackupService.new.perform

    # Record the backup in the database for the admin UI
    BackupRecord.create!(
      filename: File.basename(result.path),
      path: result.path.to_s,
      size: result.size,
      checksum: result.checksum,
      backup_type: "scheduled",
      status: "complete"
    )

    Rails.logger.info "[ScheduledBackupJob] Backup complete: #{result.path} (#{ActiveSupport::NumberHelper.number_to_human_size(result.size)})"
  rescue => error
    Rails.logger.error "[ScheduledBackupJob] Backup failed: #{error.message}"

    BackupRecord.create!(
      filename: "failed_#{Time.current.strftime('%Y%m%d_%H%M%S')}",
      backup_type: "scheduled",
      status: "failed",
      error_message: error.message
    )

    raise # Re-raise so SolidQueue marks it as failed
  end
end
```

### Retention Policy

```ruby
# app/jobs/backup_retention_cleanup_job.rb
class BackupRetentionCleanupJob < ApplicationJob
  queue_as :backups

  # Default retention: keep last 7 daily, last 4 weekly, last 3 monthly
  DAILY_RETENTION  = 7
  WEEKLY_RETENTION = 4
  MONTHLY_RETENTION = 3

  def perform
    backups = BackupRecord.where(status: "complete").order(created_at: :desc)
    return if backups.empty?

    keep = Set.new
    now = Time.current

    # Keep the N most recent daily backups
    backups.where("created_at > ?", DAILY_RETENTION.days.ago).each { |b| keep << b.id }

    # Keep one per week for the last N weeks
    (1..WEEKLY_RETENTION).each do |weeks_ago|
      week_start = now - weeks_ago.weeks
      week_end = week_start + 1.week
      weekly = backups.where(created_at: week_start..week_end).first
      keep << weekly.id if weekly
    end

    # Keep one per month for the last N months
    (1..MONTHLY_RETENTION).each do |months_ago|
      month_start = now - months_ago.months
      month_end = month_start + 1.month
      monthly = backups.where(created_at: month_start..month_end).first
      keep << monthly.id if monthly
    end

    # Delete everything not in the keep set
    to_delete = backups.where.not(id: keep.to_a)
    to_delete.find_each do |backup|
      Rails.logger.info "[BackupRetention] Removing old backup: #{backup.filename}"
      File.delete(backup.path) if File.exist?(backup.path.to_s)
      backup.destroy!
    end
  end
end
```

### BackupRecord Model

```ruby
# Migration
class CreateBackupRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_records do |t|
      t.string :filename, null: false
      t.string :path
      t.bigint :size
      t.string :checksum
      t.string :backup_type, null: false  # scheduled, manual, pre_restore, pre_import
      t.string :status, null: false       # pending, complete, failed
      t.text :error_message
      t.timestamps
    end

    add_index :backup_records, :created_at
    add_index :backup_records, :backup_type
    add_index :backup_records, :status
  end
end
```

### Backup Integrity Verification

```ruby
# app/services/backup/integrity_checker.rb
module Backup
  class IntegrityChecker
    Result = Data.define(:valid, :errors, :warnings)

    def initialize(backup_path:)
      @backup_path = Pathname.new(backup_path)
      @errors = []
      @warnings = []
    end

    def check
      check_file_exists
      check_zip_integrity
      check_manifest
      check_database_dump
      check_checksum if @errors.empty?

      Result.new(
        valid: @errors.empty?,
        errors: @errors,
        warnings: @warnings
      )
    end

    private

    def check_file_exists
      @errors << "Backup file does not exist" unless @backup_path.exist?
    end

    def check_zip_integrity
      Zip::File.open(@backup_path) do |zip|
        zip.each do |entry|
          entry.get_input_stream { |io| io.read } # Force decompression to check integrity
        end
      end
    rescue Zip::Error => e
      @errors << "ZIP file is corrupt: #{e.message}"
    end

    def check_manifest
      Zip::File.open(@backup_path) do |zip|
        entry = zip.find_entry("manifest.json")
        unless entry
          @errors << "Missing manifest.json"
          return
        end

        manifest = JSON.parse(zip.read(entry))

        unless manifest["format"] == "scanarr_backup"
          @errors << "Unknown backup format: #{manifest['format']}"
        end

        if manifest["scanarr_version"] && manifest["scanarr_version"] != Scanarr::VERSION
          @warnings << "Backup from different Scanarr version: #{manifest['scanarr_version']} (current: #{Scanarr::VERSION})"
        end
      end
    rescue JSON::ParserError
      @errors << "manifest.json is not valid JSON"
    end

    def check_database_dump
      Zip::File.open(@backup_path) do |zip|
        entry = zip.find_entry("database.sql.gz")
        unless entry
          @errors << "Missing database.sql.gz"
          return
        end

        # Verify the gzip can be decompressed and contains SQL
        content = ""
        Zlib::GzipReader.new(StringIO.new(zip.read(entry))) do |gz|
          content = gz.read(1024) # Just read the first 1KB to verify
        end

        unless content.include?("PostgreSQL") || content.include?("pg_dump")
          @warnings << "database.sql.gz does not appear to be a PostgreSQL dump"
        end
      end
    rescue Zlib::GzipFile::Error
      @errors << "database.sql.gz is not valid gzip"
    end

    def check_checksum
      Zip::File.open(@backup_path) do |zip|
        manifest = JSON.parse(zip.read("manifest.json"))
        if manifest["checksum"]
          actual = Digest::SHA256.file(@backup_path).hexdigest
          expected = manifest["checksum"].sub(/^sha256:/, "")
          if actual != expected
            @errors << "Checksum mismatch: expected #{expected}, got #{actual}"
          end
        else
          @warnings << "No checksum in manifest (older backup format)"
        end
      end
    end
  end
end
```

### Cloud Storage Destinations

For users who want off-site backups, support pluggable backup destinations using Active Storage's existing service abstraction.

```ruby
# app/services/backup/destinations/base.rb
module Backup
  module Destinations
    class Base
      def upload(local_path, remote_key)
        raise NotImplementedError
      end

      def download(remote_key, local_path)
        raise NotImplementedError
      end

      def list
        raise NotImplementedError
      end

      def delete(remote_key)
        raise NotImplementedError
      end
    end
  end
end

# app/services/backup/destinations/local.rb
module Backup
  module Destinations
    class Local < Base
      def initialize(path:)
        @path = Pathname.new(path)
        FileUtils.mkdir_p(@path)
      end

      def upload(local_path, remote_key)
        dest = @path.join(remote_key)
        FileUtils.cp(local_path, dest)
        dest
      end

      def download(remote_key, local_path)
        FileUtils.cp(@path.join(remote_key), local_path)
      end

      def list
        Dir.glob(@path.join("scanarr_backup_*.zip")).map do |f|
          { key: File.basename(f), size: File.size(f), modified: File.mtime(f) }
        end
      end

      def delete(remote_key)
        path = @path.join(remote_key)
        File.delete(path) if File.exist?(path)
      end
    end
  end
end

# app/services/backup/destinations/s3.rb
module Backup
  module Destinations
    class S3 < Base
      def initialize(bucket:, region:, access_key_id:, secret_access_key:, prefix: "scanarr/backups/")
        @bucket = bucket
        @prefix = prefix
        @client = Aws::S3::Client.new(
          region: region,
          access_key_id: access_key_id,
          secret_access_key: secret_access_key
        )
      end

      def upload(local_path, remote_key)
        File.open(local_path, "rb") do |file|
          @client.put_object(
            bucket: @bucket,
            key: "#{@prefix}#{remote_key}",
            body: file,
            server_side_encryption: "AES256"
          )
        end
      end

      def download(remote_key, local_path)
        @client.get_object(
          bucket: @bucket,
          key: "#{@prefix}#{remote_key}",
          response_target: local_path
        )
      end

      def list
        response = @client.list_objects_v2(bucket: @bucket, prefix: @prefix)
        response.contents.map do |obj|
          { key: obj.key.sub(@prefix, ""), size: obj.size, modified: obj.last_modified }
        end
      end

      def delete(remote_key)
        @client.delete_object(bucket: @bucket, key: "#{@prefix}#{remote_key}")
      end
    end
  end
end
```

**Configuration** (via environment variables or future admin settings):

```yaml
# config/backup.yml
default: &default
  enabled: true
  schedule: "at 3am every day"
  destination: local
  local:
    path: <%= Rails.root.join("storage/backups") %>
  retention:
    daily: 7
    weekly: 4
    monthly: 3

production:
  <<: *default
  # Override with env vars for cloud storage:
  # SCANARR_BACKUP_DESTINATION=s3
  # SCANARR_BACKUP_S3_BUCKET=my-backups
  # SCANARR_BACKUP_S3_REGION=us-east-1
  # SCANARR_BACKUP_S3_ACCESS_KEY=...
  # SCANARR_BACKUP_S3_SECRET_KEY=...
```

---

## 3. Library Export/Import (Portable Format)

This is the Mihon-equivalent feature: export your entire library configuration as a portable file that can be imported into another Scanarr instance. No binary files (images, archives) are included -- only metadata.

### Export Format: `.scanarr` (JSON + GZip)

We use JSON rather than protobuf for several reasons:
- Easier to debug and inspect (human-readable when decompressed)
- No schema compilation step needed
- Ruby has excellent JSON support built in
- Users can manually edit exports if needed
- Simpler implementation for a Rails app

The file is a GZipped JSON file with `.scanarr` extension (analogous to Mihon's `.tachibk`).

### Export Schema

```json
{
  "format": "scanarr_library_export",
  "version": 1,
  "created_at": "2026-02-05T12:00:00Z",
  "scanarr_version": "0.1.0",

  "sources": [
    {
      "key": "mangadex",
      "slug": "mangadex",
      "name": "MangaDex",
      "base_url": "https://api.mangadex.org",
      "enabled": true
    }
  ],

  "library_series": [
    {
      "canonical_title": "Solo Leveling",
      "status": "completed",
      "anilist_id": 105398,
      "mal_id": 121496,
      "mangadex_id": "32d76d19-8a05-4db0-9fc2-e0b0648fe9d0",
      "series": [
        {
          "canonical_title": "Solo Leveling",
          "cover_url": "https://...",
          "author_name": "Chugong",
          "artist_name": "Dubu (Redice Studio)",
          "description": "...",
          "status": "completed",
          "series_type": "manhwa",
          "reading_style": "webtoon",
          "language_policy": "en",
          "raw_tags": ["action", "adventure", "fantasy"],
          "normalized_categories": ["action", "adventure"],
          "alt_titles": ["Na Honjaman Level Up"],
          "source_mappings": [
            {
              "source_key": "mangadex",
              "source_series_id": "32d76d19-8a05-4db0-9fc2-e0b0648fe9d0",
              "library_base_path": "/manga/Solo Leveling/MangaDex"
            }
          ],
          "chapters": [
            {
              "chapter_number": "1",
              "chapter_number_value": "1.0",
              "title": "Prologue",
              "language": "en",
              "group": null,
              "source_url": "https://mangadex.org/chapter/...",
              "source_key": "mangadex",
              "published_at": "2020-01-01T00:00:00Z",
              "volume_number": "1"
            }
          ]
        }
      ]
    }
  ],

  "reading_progress": [
    {
      "series_title": "Solo Leveling",
      "chapter_number": "45",
      "page_index": 12,
      "page_count": 25,
      "status": "in_progress",
      "progressed_at": "2026-02-04T20:30:00Z"
    }
  ],

  "follows": [
    {
      "series_title": "Solo Leveling",
      "download_policy": "auto_download",
      "source_priority": ["mangadex", "weeb_central"]
    }
  ],

  "categories": []
}
```

### What's Included vs Excluded

| Included | Excluded |
|----------|----------|
| Library series metadata | Downloaded chapter files (pages, archives) |
| Series-source mappings | Active Storage blobs |
| Chapter list with source URLs | SolidQueue job state |
| Reading progress (page, status) | Scraper run history |
| Follow settings + download policies | Session/auth data |
| Source configurations | Notification read state |
| Tags and categories | File asset download state |
| External IDs (AniList, MAL, MangaDex) | |
| Volume information | |

### Export Service

```ruby
# app/services/library_export_service.rb
class LibraryExportService
  EXPORT_VERSION = 1

  def initialize(user:)
    @user = user
  end

  def perform
    export_data = {
      format: "scanarr_library_export",
      version: EXPORT_VERSION,
      created_at: Time.current.iso8601,
      scanarr_version: Scanarr::VERSION,
      sources: export_sources,
      library_series: export_library_series,
      reading_progress: export_reading_progress,
      follows: export_follows
    }

    # Compress as gzip
    compressed = StringIO.new
    Zlib::GzipWriter.wrap(compressed) do |gz|
      gz.write(JSON.generate(export_data))
    end

    compressed.string
  end

  private

  def export_sources
    Source.all.map do |source|
      {
        key: source.key,
        slug: source.slug,
        name: source.name,
        base_url: source.base_url,
        enabled: source.enabled,
        default_priority: source.default_priority
      }
    end
  end

  def export_library_series
    LibrarySeries.includes(
      series: [ :sources, :series_sources, :chapters, :volumes ]
    ).map do |ls|
      {
        canonical_title: ls.canonical_title,
        status: ls.status,
        anilist_id: ls.anilist_id,
        mal_id: ls.mal_id,
        mangadex_id: ls.mangadex_id,
        series: ls.series.map { |s| export_series(s) }
      }
    end
  end

  def export_series(series)
    {
      canonical_title: series.canonical_title,
      cover_url: series.cover_url,
      author_name: series.author_name,
      artist_name: series.artist_name,
      description: series.description,
      status: series.status,
      series_type: series.series_type,
      reading_style: series.reading_style,
      language_policy: series.language_policy,
      raw_tags: series.raw_tags,
      normalized_categories: series.normalized_categories,
      alt_titles: series.alt_titles,
      localized_title: series.localized_title,
      source_mappings: series.series_sources.map do |ss|
        {
          source_key: ss.source.key,
          source_series_id: ss.source_series_id,
          library_base_path: ss.library_base_path
        }
      end,
      chapters: series.chapters.order(:chapter_number_value).map do |ch|
        {
          chapter_number: ch.chapter_number,
          chapter_number_value: ch.chapter_number_value&.to_f,
          title: ch.title,
          language: ch.language,
          group: ch.group,
          source_url: ch.source_url,
          source_key: ch.source&.key,
          published_at: ch.published_at&.iso8601,
          volume_number: ch.volume&.volume_number
        }
      end
    }
  end

  def export_reading_progress
    @user.chapter_progresses.includes(chapter: :series).map do |cp|
      {
        series_title: cp.chapter.series.canonical_title,
        chapter_number: cp.chapter.chapter_number,
        page_index: cp.page_index,
        page_count: cp.page_count,
        status: cp.status,
        progressed_at: cp.progressed_at.iso8601
      }
    end
  end

  def export_follows
    @user.user_series_follows.includes(:library_series).map do |follow|
      {
        series_title: follow.library_series.canonical_title,
        download_policy: follow.download_policy,
        source_priority: follow.source_priority
      }
    end
  end
end
```

### Import Service with Merge/Overwrite Strategy

```ruby
# app/services/library_import_service.rb
class LibraryImportService
  SUPPORTED_VERSIONS = [ 1 ].freeze

  # Strategy options:
  #   :merge      - Add new data, skip existing, keep newer reading progress
  #   :overwrite  - Replace all data from the import
  #   :skip       - Only add series/chapters that don't exist yet
  Strategy = Data.define(:series, :progress, :follows)

  Result = Data.define(:success, :imported, :skipped, :errors)

  DEFAULT_STRATEGY = Strategy.new(
    series: :merge,
    progress: :merge,    # keep whichever is newer
    follows: :merge
  )

  def initialize(data:, user:, strategy: DEFAULT_STRATEGY, dry_run: false)
    @data = data
    @user = user
    @strategy = strategy
    @dry_run = dry_run
    @imported = { series: 0, chapters: 0, progress: 0, follows: 0 }
    @skipped = { series: 0, chapters: 0, progress: 0, follows: 0 }
    @errors = []
  end

  def perform
    validate_format!
    parsed = parse_data

    ActiveRecord::Base.transaction do
      import_sources(parsed["sources"])
      import_library_series(parsed["library_series"])
      import_reading_progress(parsed["reading_progress"])
      import_follows(parsed["follows"])

      raise ActiveRecord::Rollback if @dry_run
    end

    Result.new(
      success: @errors.empty?,
      imported: @imported,
      skipped: @skipped,
      errors: @errors
    )
  end

  private

  def validate_format!
    # Handle both raw JSON and gzipped data
    @raw_data = if @data.is_a?(String) && @data.start_with?("\x1f\x8b".b)
      Zlib::GzipReader.new(StringIO.new(@data)).read
    elsif @data.is_a?(String)
      @data
    else
      raise "Unsupported import data format"
    end
  end

  def parse_data
    parsed = JSON.parse(@raw_data)

    unless parsed["format"] == "scanarr_library_export"
      raise "Unknown export format: #{parsed['format']}"
    end

    unless SUPPORTED_VERSIONS.include?(parsed["version"])
      raise "Unsupported export version: #{parsed['version']}"
    end

    parsed
  end

  def import_sources(sources_data)
    return unless sources_data

    sources_data.each do |source_data|
      Source.find_or_create_by!(key: source_data["key"]) do |source|
        source.name = source_data["name"]
        source.base_url = source_data["base_url"]
        source.enabled = source_data.fetch("enabled", true)
        source.default_priority = source_data.fetch("default_priority", 50)
      end
    end
  end

  def import_library_series(library_series_data)
    return unless library_series_data

    library_series_data.each do |ls_data|
      ls = LibrarySeries.find_or_initialize_by(canonical_title: ls_data["canonical_title"])

      if ls.persisted? && @strategy.series == :skip
        @skipped[:series] += 1
        next
      end

      if ls.new_record? || @strategy.series == :overwrite
        ls.assign_attributes(
          status: ls_data["status"],
          anilist_id: ls_data["anilist_id"],
          mal_id: ls_data["mal_id"],
          mangadex_id: ls_data["mangadex_id"]
        )
      elsif @strategy.series == :merge
        # Only fill in missing external IDs
        ls.anilist_id ||= ls_data["anilist_id"]
        ls.mal_id ||= ls_data["mal_id"]
        ls.mangadex_id ||= ls_data["mangadex_id"]
      end

      ls.save!
      @imported[:series] += 1

      # Import the source-specific series under this LibrarySeries
      ls_data["series"]&.each do |series_data|
        import_series(series_data, ls)
      end
    rescue => e
      @errors << "Failed to import library series '#{ls_data['canonical_title']}': #{e.message}"
    end
  end

  def import_series(series_data, library_series)
    # Try to match by source mapping first, then by title
    series = nil

    series_data["source_mappings"]&.each do |mapping|
      source = Source.find_by(key: mapping["source_key"])
      next unless source

      ss = SeriesSource.find_by(source: source, source_series_id: mapping["source_series_id"])
      if ss
        series = ss.series
        break
      end
    end

    series ||= Series.find_by(canonical_title: series_data["canonical_title"], library_series: library_series)

    if series && @strategy.series == :skip
      @skipped[:series] += 1
      return
    end

    series ||= Series.new(canonical_title: series_data["canonical_title"])
    series.library_series = library_series

    if series.new_record? || @strategy.series == :overwrite
      series.assign_attributes(
        cover_url: series_data["cover_url"],
        author_name: series_data["author_name"],
        artist_name: series_data["artist_name"],
        description: series_data["description"],
        status: series_data["status"],
        series_type: series_data["series_type"],
        reading_style: series_data["reading_style"],
        language_policy: series_data["language_policy"],
        raw_tags: series_data["raw_tags"] || [],
        normalized_categories: series_data["normalized_categories"] || [],
        alt_titles: series_data["alt_titles"] || [],
        localized_title: series_data["localized_title"]
      )
    end

    series.save!

    # Create source mappings
    series_data["source_mappings"]&.each do |mapping|
      source = Source.find_by(key: mapping["source_key"])
      next unless source

      SeriesSource.find_or_create_by!(series: series, source: source) do |ss|
        ss.source_series_id = mapping["source_series_id"]
        ss.library_base_path = mapping["library_base_path"]
      end
    end

    # Import chapters
    series_data["chapters"]&.each do |ch_data|
      import_chapter(ch_data, series)
    end
  end

  def import_chapter(chapter_data, series)
    source = chapter_data["source_key"] ? Source.find_by(key: chapter_data["source_key"]) : nil

    chapter = Chapter.find_or_initialize_by(
      series: series,
      chapter_number: chapter_data["chapter_number"],
      language: chapter_data["language"],
      group: chapter_data["group"]
    )

    if chapter.persisted? && @strategy.series == :skip
      @skipped[:chapters] += 1
      return
    end

    if chapter.new_record? || @strategy.series != :skip
      chapter.assign_attributes(
        title: chapter_data["title"],
        source: source,
        source_url: chapter_data["source_url"],
        published_at: chapter_data["published_at"]
      )

      # Link to volume if specified
      if chapter_data["volume_number"]
        volume = Volume.find_or_create_by!(
          series: series,
          volume_number: chapter_data["volume_number"]
        )
        chapter.volume = volume
      end

      chapter.save!
      @imported[:chapters] += 1
    end
  end

  def import_reading_progress(progress_data)
    return unless progress_data

    progress_data.each do |prog|
      series = Series.find_by(canonical_title: prog["series_title"])
      next unless series

      chapter = series.chapters.find_by(chapter_number: prog["chapter_number"])
      next unless chapter

      existing = ChapterProgress.find_by(user: @user, chapter: chapter)

      case @strategy.progress
      when :skip
        if existing
          @skipped[:progress] += 1
          next
        end
      when :merge
        # Keep whichever is more recent
        if existing && existing.progressed_at >= Time.parse(prog["progressed_at"])
          @skipped[:progress] += 1
          next
        end
      end

      cp = existing || ChapterProgress.new(user: @user, chapter: chapter)
      cp.assign_attributes(
        page_index: prog["page_index"],
        page_count: prog["page_count"],
        status: prog["status"],
        progressed_at: prog["progressed_at"]
      )
      cp.save!
      @imported[:progress] += 1
    rescue => e
      @errors << "Failed to import progress for #{prog['series_title']} ch.#{prog['chapter_number']}: #{e.message}"
    end
  end

  def import_follows(follows_data)
    return unless follows_data

    follows_data.each do |follow_data|
      ls = LibrarySeries.find_by(canonical_title: follow_data["series_title"])
      next unless ls

      existing = UserSeriesFollow.find_by(user: @user, library_series: ls)

      if existing && @strategy.follows == :skip
        @skipped[:follows] += 1
        next
      end

      follow = existing || UserSeriesFollow.new(user: @user, library_series: ls)
      follow.assign_attributes(
        download_policy: follow_data["download_policy"],
        source_priority: follow_data["source_priority"] || []
      )
      follow.save!
      @imported[:follows] += 1
    rescue => e
      @errors << "Failed to import follow for '#{follow_data['series_title']}': #{e.message}"
    end
  end
end
```

### Rake Tasks for CLI Usage

```ruby
# lib/tasks/backup.rake
namespace :scanarr do
  namespace :backup do
    desc "Create a full database backup"
    task create: :environment do
      puts "Creating backup..."
      result = Backup::DatabaseBackupService.new.perform
      puts "Backup created: #{result.path}"
      puts "Size: #{ActiveSupport::NumberHelper.number_to_human_size(result.size)}"
      puts "Checksum: sha256:#{result.checksum}"
    end

    desc "Restore from a backup file"
    task :restore, [ :path ] => :environment do |_t, args|
      path = args[:path]
      abort "Usage: rake scanarr:backup:restore[/path/to/backup.zip]" unless path

      puts "Validating backup..."
      integrity = Backup::IntegrityChecker.new(backup_path: path).check
      unless integrity.valid
        abort "Backup validation failed:\n#{integrity.errors.join("\n")}"
      end

      puts "Integrity check passed."
      integrity.warnings.each { |w| puts "WARNING: #{w}" }

      puts "\nDry run..."
      dry_result = Backup::DatabaseRestoreService.new(backup_path: path, dry_run: true).perform
      puts "Tables to restore: #{dry_result.tables_restored.keys.join(', ')}"

      print "\nProceed with restore? This will OVERWRITE the current database. [y/N] "
      answer = $stdin.gets&.strip
      abort "Aborted." unless answer&.downcase == "y"

      puts "Restoring..."
      result = Backup::DatabaseRestoreService.new(backup_path: path).perform

      if result.success
        puts "Restore complete!"
      else
        puts "Restore completed with errors:"
        result.errors.each { |e| puts "  - #{e}" }
      end
    end

    desc "Verify a backup file's integrity"
    task :verify, [ :path ] => :environment do |_t, args|
      path = args[:path]
      abort "Usage: rake scanarr:backup:verify[/path/to/backup.zip]" unless path

      result = Backup::IntegrityChecker.new(backup_path: path).check
      if result.valid
        puts "Backup is valid."
        result.warnings.each { |w| puts "WARNING: #{w}" }
      else
        puts "Backup is INVALID:"
        result.errors.each { |e| puts "  ERROR: #{e}" }
        result.warnings.each { |w| puts "  WARNING: #{w}" }
        exit 1
      end
    end

    desc "List all backups"
    task list: :environment do
      backups = BackupRecord.order(created_at: :desc)
      if backups.empty?
        puts "No backups found."
      else
        backups.each do |b|
          size = b.size ? ActiveSupport::NumberHelper.number_to_human_size(b.size) : "unknown"
          puts "#{b.created_at.strftime('%Y-%m-%d %H:%M')}  #{b.backup_type.ljust(12)}  #{b.status.ljust(8)}  #{size}  #{b.filename}"
        end
      end
    end

    desc "Run retention cleanup now"
    task cleanup: :environment do
      puts "Running retention cleanup..."
      BackupRetentionCleanupJob.perform_now
      puts "Done."
    end
  end

  namespace :export do
    desc "Export library to .scanarr file"
    task :library, [ :output ] => :environment do |_t, args|
      output = args[:output] || "scanarr_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.scanarr"
      user = User.first || abort("No user found")

      puts "Exporting library..."
      data = LibraryExportService.new(user: user).perform
      File.binwrite(output, data)
      puts "Export saved to: #{output}"
      puts "Size: #{ActiveSupport::NumberHelper.number_to_human_size(File.size(output))}"
    end

    desc "Import library from .scanarr file"
    task :import, [ :path, :strategy ] => :environment do |_t, args|
      path = args[:path]
      abort "Usage: rake scanarr:export:import[/path/to/export.scanarr,merge|overwrite|skip]" unless path

      strategy_name = (args[:strategy] || "merge").to_sym
      strategy = LibraryImportService::Strategy.new(
        series: strategy_name,
        progress: strategy_name,
        follows: strategy_name
      )

      user = User.first || abort("No user found")
      data = File.binread(path)

      # Dry run first
      puts "Dry run..."
      dry_result = LibraryImportService.new(
        data: data, user: user, strategy: strategy, dry_run: true
      ).perform
      puts "Would import: #{dry_result.imported}"
      puts "Would skip: #{dry_result.skipped}"

      print "\nProceed? [y/N] "
      answer = $stdin.gets&.strip
      abort "Aborted." unless answer&.downcase == "y"

      puts "Importing with strategy: #{strategy_name}..."
      result = LibraryImportService.new(
        data: data, user: user, strategy: strategy
      ).perform

      puts "Import #{result.success ? 'complete' : 'completed with errors'}!"
      puts "Imported: #{result.imported}"
      puts "Skipped: #{result.skipped}"
      result.errors.each { |e| puts "  ERROR: #{e}" } if result.errors.any?
    end
  end
end
```

---

## 4. Settings Export/Import

Separate from library data, this covers app-level configuration that is lightweight and useful for cloning setups or sharing configurations between instances.

### Settings Export Format

```json
{
  "format": "scanarr_settings",
  "version": 1,
  "created_at": "2026-02-05T12:00:00Z",

  "sources": {
    "mangadex": {
      "enabled": true,
      "default_priority": 50,
      "config": {
        "base_url": "https://api.mangadex.org",
        "delay_ms": 200,
        "open_timeout": 10,
        "read_timeout": 20,
        "max_retries": 2
      }
    },
    "weeb_central": {
      "enabled": true,
      "default_priority": 50,
      "config": {
        "base_url": "https://weebcentral.com",
        "delay_ms": 400
      }
    }
  },

  "backup": {
    "enabled": true,
    "schedule": "at 3am every day",
    "retention": { "daily": 7, "weekly": 4, "monthly": 3 },
    "destination": "local"
  },

  "user_preferences": {
    "default_reading_style": "right_to_left",
    "default_download_policy": "notify_only",
    "chapter_check_interval_minutes": 30
  }
}
```

### Settings Service

```ruby
# app/services/settings_export_service.rb
class SettingsExportService
  def perform
    {
      format: "scanarr_settings",
      version: 1,
      created_at: Time.current.iso8601,
      sources: export_source_settings,
      backup: export_backup_settings,
      user_preferences: export_user_preferences
    }.to_json
  end

  private

  def export_source_settings
    sources = {}
    Source.all.each do |source|
      config = Rails.application.config.scraper_sources&.dig(source.key) || {}
      sources[source.key] = {
        enabled: source.enabled,
        default_priority: source.default_priority,
        config: config.except("proxy_url") # Don't export proxy settings
      }
    end
    sources
  end

  def export_backup_settings
    backup_config = Rails.application.config_for(:backup) rescue {}
    {
      enabled: backup_config[:enabled],
      schedule: backup_config[:schedule],
      retention: backup_config[:retention],
      destination: backup_config[:destination]
    }
  end

  def export_user_preferences
    # Future: read from a UserPreference model or application config
    {
      default_reading_style: "right_to_left",
      default_download_policy: "notify_only",
      chapter_check_interval_minutes: 30
    }
  end
end

# app/services/settings_import_service.rb
class SettingsImportService
  def initialize(data:, sections: :all)
    @data = JSON.parse(data.is_a?(String) ? data : data.read)
    @sections = sections # :all, or array of [:sources, :backup, :user_preferences]
  end

  def perform
    errors = []

    if should_import?(:sources)
      errors += import_source_settings
    end

    # backup and user_preferences are config-file based,
    # so we generate the files but don't auto-apply
    if should_import?(:backup)
      errors += generate_backup_config
    end

    { success: errors.empty?, errors: errors }
  end

  private

  def should_import?(section)
    @sections == :all || Array(@sections).include?(section)
  end

  def import_source_settings
    errors = []
    @data["sources"]&.each do |key, settings|
      source = Source.find_by(key: key)
      if source
        source.update!(
          enabled: settings.fetch("enabled", source.enabled),
          default_priority: settings.fetch("default_priority", source.default_priority)
        )
      end
    rescue => e
      errors << "Failed to update source '#{key}': #{e.message}"
    end
    errors
  end

  def generate_backup_config
    # Write a new backup.yml based on imported settings
    # User must restart for changes to take effect
    []
  end
end
```

---

## 5. Mihon Compatibility Layer

### Can We Import from Mihon Backups?

**Yes, partially.** The Mihon `.tachibk` format is protobuf + gzip. We can parse it and map the data to Scanarr's data model.

### Source Mapping

The critical challenge is mapping Mihon's numeric source IDs to Scanarr's source keys. Mihon identifies sources by a 64-bit integer hash of the source class name. We need a lookup table.

```ruby
# app/services/mihon/source_mapping.rb
module Mihon
  SOURCE_MAP = {
    # Source ID => Scanarr source key
    # These IDs come from Mihon's extension source hash
    2499283573021220255 => "mangadex",
    1998944621602463790 => "manga_see",
    # ... more mappings added as we discover them
  }.freeze

  # Reverse mapping: Scanarr key => Mihon source ID
  REVERSE_SOURCE_MAP = SOURCE_MAP.invert.freeze

  def self.scanarr_source_for(mihon_source_id)
    SOURCE_MAP[mihon_source_id]
  end

  def self.mihon_source_id_for(scanarr_key)
    REVERSE_SOURCE_MAP[scanarr_key]
  end
end
```

### Mihon Import Service

To parse protobuf in Ruby, we can use the `google-protobuf` gem. However, a simpler approach is to convert the `.tachibk` to JSON first (the protobuf schema is well-known), then process the JSON.

**Approach: Use the protobuf gem with a generated Ruby schema.**

```ruby
# Gemfile addition:
# gem "google-protobuf", "~> 4.0"

# lib/mihon/backup_pb.rb (generated from tachiyomi.proto)
# This file would be auto-generated from the Mihon protobuf schema.
# For now, we can use a JSON intermediate approach.

# app/services/mihon/import_service.rb
module Mihon
  class ImportService
    Result = Data.define(:success, :imported, :skipped, :unmapped_sources, :errors)

    def initialize(file_data:, user:, strategy: :merge)
      @file_data = file_data
      @user = user
      @strategy = strategy
      @imported = { series: 0, chapters: 0, progress: 0 }
      @skipped = { series: 0, chapters: 0, progress: 0 }
      @unmapped_sources = Set.new
      @errors = []
    end

    def perform
      backup_data = parse_tachibk(@file_data)

      # First pass: identify which sources we can map
      source_report = analyze_sources(backup_data["backupSources"] || [])

      ActiveRecord::Base.transaction do
        (backup_data["backupManga"] || []).each do |manga|
          import_manga(manga)
        end
      end

      Result.new(
        success: @errors.length < 5, # Allow some partial failures
        imported: @imported,
        skipped: @skipped,
        unmapped_sources: @unmapped_sources.to_a,
        errors: @errors
      )
    end

    private

    def parse_tachibk(data)
      # Decompress gzip
      decompressed = Zlib::GzipReader.new(StringIO.new(data)).read

      # Parse protobuf - requires the generated Ruby protobuf class
      # Alternatively, use a JSON conversion step
      backup = Mihon::Backup.decode(decompressed)
      JSON.parse(Mihon::Backup.encode_json(backup))
    rescue => e
      raise "Failed to parse .tachibk file: #{e.message}"
    end

    def analyze_sources(backup_sources)
      report = { mapped: [], unmapped: [] }
      backup_sources.each do |source|
        scanarr_key = Mihon.scanarr_source_for(source["sourceId"])
        if scanarr_key
          report[:mapped] << { mihon_name: source["name"], scanarr_key: scanarr_key }
        else
          report[:unmapped] << { mihon_name: source["name"], mihon_id: source["sourceId"] }
          @unmapped_sources << source["name"]
        end
      end
      report
    end

    def import_manga(manga_data)
      source_id = manga_data["source"]
      scanarr_key = Mihon.scanarr_source_for(source_id)

      unless scanarr_key
        @skipped[:series] += 1
        return
      end

      source = Source.find_or_create_by!(key: scanarr_key) do |s|
        s.name = scanarr_key.tr("_", " ").titleize
      end

      title = manga_data["title"].presence || "Unknown"

      # Find or create LibrarySeries
      library_series = LibrarySeries.find_or_create_by!(canonical_title: title)

      # Find or create Series
      series = Series.find_or_initialize_by(
        canonical_title: title,
        library_series: library_series
      )

      series.assign_attributes(
        cover_url: manga_data["thumbnailUrl"],
        author_name: manga_data["author"],
        artist_name: manga_data["artist"],
        description: manga_data["description"],
        status: mihon_status_to_string(manga_data["status"]),
        reading_style: mihon_viewer_to_reading_style(manga_data["viewer"]),
        raw_tags: manga_data["genre"] || []
      )
      series.save!

      # Create source mapping
      # Mihon stores the manga URL relative to the source
      SeriesSource.find_or_create_by!(series: series, source: source) do |ss|
        ss.source_series_id = manga_data["url"]
      end

      @imported[:series] += 1

      # Import chapters
      (manga_data["chapters"] || []).each do |chapter_data|
        import_mihon_chapter(chapter_data, series, source)
      end

      # Import reading history
      (manga_data["history"] || []).each do |history_data|
        import_mihon_history(history_data, series)
      end

      # Create follow if it was a favorite
      if manga_data["favorite"]
        UserSeriesFollow.find_or_create_by!(
          user: @user,
          library_series: library_series
        ) do |follow|
          follow.download_policy = :notify_only
        end
      end
    rescue => e
      @errors << "Failed to import '#{manga_data['title']}': #{e.message}"
    end

    def import_mihon_chapter(chapter_data, series, source)
      chapter_number = chapter_data["chapterNumber"]&.to_s
      chapter_number = chapter_data["name"] if chapter_number.blank? || chapter_number == "0.0"

      chapter = Chapter.find_or_initialize_by(
        series: series,
        chapter_number: chapter_number.to_s,
        language: "en" # Mihon doesn't always store language per chapter
      )

      if chapter.new_record?
        chapter.assign_attributes(
          title: chapter_data["name"],
          source: source,
          source_url: chapter_data["url"],
          group: chapter_data["scanlator"]
        )
        chapter.save!
        @imported[:chapters] += 1
      else
        @skipped[:chapters] += 1
      end

      # Import read status
      if chapter_data["read"] && chapter.persisted?
        ChapterProgress.find_or_create_by!(user: @user, chapter: chapter) do |cp|
          cp.page_index = chapter_data["lastPageRead"] || 0
          cp.page_count = chapter_data["lastPageRead"] || 1
          cp.status = "completed"
          cp.progressed_at = Time.at(chapter_data["dateFetch"].to_i / 1000) rescue Time.current
        end
        @imported[:progress] += 1
      end
    rescue => e
      @errors << "Failed to import chapter #{chapter_data['name']}: #{e.message}"
    end

    def import_mihon_history(history_data, series)
      # Mihon history contains URL + lastRead timestamp
      url = history_data["url"]
      chapter = series.chapters.find_by(source_url: url)
      return unless chapter

      ChapterProgress.find_or_create_by!(user: @user, chapter: chapter) do |cp|
        cp.page_index = 0
        cp.page_count = 1
        cp.status = "completed"
        cp.progressed_at = Time.at(history_data["lastRead"].to_i / 1000) rescue Time.current
      end
    rescue ActiveRecord::RecordInvalid
      # Progress already exists, skip
    end

    def mihon_status_to_string(status_int)
      case status_int
      when 1 then "ongoing"
      when 2 then "completed"
      when 3 then "licensed"
      when 4 then "publishing_finished"
      when 5 then "cancelled"
      when 6 then "hiatus"
      else "unknown"
      end
    end

    def mihon_viewer_to_reading_style(viewer_int)
      case viewer_int
      when 1 then "left_to_right"
      when 2 then "right_to_left"
      when 3 then "vertical"
      when 4 then "webtoon"
      when 5 then "continuous_vertical"
      else nil # Use series default
      end
    end
  end
end
```

### Can We Export for Mihon?

**Not a priority, but technically possible.** We would need to:

1. Serialize Scanarr data into the Mihon protobuf schema
2. Map Scanarr source keys to Mihon's numeric source IDs
3. GZip and save as `.tachibk`

The main challenge is that Mihon's source IDs are hashes of Java class names from specific extensions. A Mihon user would need the correct extensions installed for the import to work. This is fragile and low-value compared to the import direction.

**Recommendation**: Implement Mihon import as Phase 3. Do not implement Mihon export unless there is strong demand.

---

## 6. Admin UI

### Backup Management Page

Located at `/admin/backups`, accessible to authenticated users.

```
Admin > Backups
+------------------------------------------------------+
|  [Create Backup Now]    [Upload Backup]               |
|                                                       |
|  Backup Settings                                      |
|  Schedule: [every day at 3am  v]                     |
|  Retention: [7] daily  [4] weekly  [3] monthly       |
|  Destination: [Local Filesystem v]                    |
|  Path: /app/storage/backups                           |
|  [Save Settings]                                      |
|                                                       |
|  Recent Backups                                       |
|  +-----------+---------+--------+---------+--------+  |
|  | Date      | Type    | Status | Size    | Actions|  |
|  +-----------+---------+--------+---------+--------+  |
|  | Feb 5 3am | sched.  | OK     | 12.4 MB | [DL][X]| |
|  | Feb 4 3am | sched.  | OK     | 12.3 MB | [DL][X]| |
|  | Feb 3 11pm| manual  | OK     | 12.3 MB | [DL][X]| |
|  +-----------+---------+--------+---------+--------+  |
|                                                       |
|  Export / Import                                      |
|  [Export Library (.scanarr)]                          |
|  [Import Library] [Import from Mihon (.tachibk)]      |
|  [Export Settings] [Import Settings]                  |
+------------------------------------------------------+
```

### Controller Structure

```ruby
# app/controllers/admin/backups_controller.rb
module Admin
  class BackupsController < ApplicationController
    before_action :authenticate!

    def index
      @backups = BackupRecord.order(created_at: :desc).page(params[:page])
    end

    def create
      result = Backup::DatabaseBackupService.new.perform
      BackupRecord.create!(
        filename: File.basename(result.path),
        path: result.path.to_s,
        size: result.size,
        checksum: result.checksum,
        backup_type: "manual",
        status: "complete"
      )
      redirect_to admin_backups_path, notice: "Backup created successfully."
    rescue => e
      redirect_to admin_backups_path, alert: "Backup failed: #{e.message}"
    end

    def download
      backup = BackupRecord.find(params[:id])
      if File.exist?(backup.path)
        send_file backup.path, filename: backup.filename, type: "application/zip"
      else
        redirect_to admin_backups_path, alert: "Backup file not found on disk."
      end
    end

    def destroy
      backup = BackupRecord.find(params[:id])
      File.delete(backup.path) if backup.path && File.exist?(backup.path)
      backup.destroy!
      redirect_to admin_backups_path, notice: "Backup deleted."
    end

    def restore
      backup = BackupRecord.find(params[:id])

      # Always verify first
      integrity = Backup::IntegrityChecker.new(backup_path: backup.path).check
      unless integrity.valid
        redirect_to admin_backups_path, alert: "Backup integrity check failed: #{integrity.errors.join(', ')}"
        return
      end

      result = Backup::DatabaseRestoreService.new(backup_path: backup.path).perform

      if result.success
        redirect_to admin_backups_path, notice: "Database restored successfully."
      else
        redirect_to admin_backups_path, alert: "Restore completed with errors: #{result.errors.join(', ')}"
      end
    end

    # Library export
    def export_library
      user = current_user
      data = LibraryExportService.new(user: user).perform
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      send_data data,
        filename: "scanarr_library_#{timestamp}.scanarr",
        type: "application/gzip"
    end

    # Library import
    def import_library
      file = params[:file]
      strategy_name = params[:strategy]&.to_sym || :merge
      strategy = LibraryImportService::Strategy.new(
        series: strategy_name,
        progress: strategy_name,
        follows: strategy_name
      )

      result = LibraryImportService.new(
        data: file.read,
        user: current_user,
        strategy: strategy
      ).perform

      if result.success
        redirect_to admin_backups_path,
          notice: "Import complete. #{result.imported[:series]} series, #{result.imported[:chapters]} chapters imported."
      else
        redirect_to admin_backups_path,
          alert: "Import had errors: #{result.errors.first(3).join('; ')}"
      end
    end

    # Mihon import
    def import_mihon
      file = params[:file]
      result = Mihon::ImportService.new(
        file_data: file.read,
        user: current_user,
        strategy: :merge
      ).perform

      messages = []
      messages << "Imported: #{result.imported[:series]} series, #{result.imported[:chapters]} chapters"
      messages << "Unmapped sources: #{result.unmapped_sources.join(', ')}" if result.unmapped_sources.any?
      messages << "Errors: #{result.errors.first(3).join('; ')}" if result.errors.any?

      redirect_to admin_backups_path, notice: messages.join(". ")
    end
  end
end
```

### Routes

```ruby
# config/routes.rb (within admin namespace)
namespace :admin do
  resources :backups, only: [ :index, :create, :destroy ] do
    member do
      get :download
      post :restore
    end
    collection do
      get :export_library
      post :import_library
      post :import_mihon
      get :export_settings
      post :import_settings
    end
  end
end
```

---

## 7. API Endpoints

For programmatic access (Docker health checks, external backup tools, CI/CD).

```ruby
# app/controllers/api/v1/backups_controller.rb
module Api
  module V1
    class BackupsController < ApplicationController
      before_action :authenticate!
      skip_before_action :verify_authenticity_token

      # GET /api/v1/backups
      def index
        backups = BackupRecord.order(created_at: :desc).limit(50)
        render json: backups.map { |b|
          {
            id: b.id,
            filename: b.filename,
            size: b.size,
            checksum: b.checksum,
            backup_type: b.backup_type,
            status: b.status,
            created_at: b.created_at.iso8601,
            download_url: download_api_v1_backup_url(b)
          }
        }
      end

      # POST /api/v1/backups
      def create
        result = Backup::DatabaseBackupService.new.perform
        backup = BackupRecord.create!(
          filename: File.basename(result.path),
          path: result.path.to_s,
          size: result.size,
          checksum: result.checksum,
          backup_type: "api",
          status: "complete"
        )

        render json: {
          id: backup.id,
          filename: backup.filename,
          size: backup.size,
          checksum: backup.checksum,
          download_url: download_api_v1_backup_url(backup)
        }, status: :created
      end

      # GET /api/v1/backups/:id/download
      def download
        backup = BackupRecord.find(params[:id])
        if File.exist?(backup.path.to_s)
          send_file backup.path, filename: backup.filename, type: "application/zip"
        else
          render json: { error: "Backup file not found" }, status: :not_found
        end
      end

      # DELETE /api/v1/backups/:id
      def destroy
        backup = BackupRecord.find(params[:id])
        File.delete(backup.path) if backup.path && File.exist?(backup.path)
        backup.destroy!
        head :no_content
      end

      # POST /api/v1/backups/:id/verify
      def verify
        backup = BackupRecord.find(params[:id])
        result = Backup::IntegrityChecker.new(backup_path: backup.path).check
        render json: {
          valid: result.valid,
          errors: result.errors,
          warnings: result.warnings
        }
      end

      # GET /api/v1/exports/library
      def export_library
        data = LibraryExportService.new(user: current_user).perform
        send_data data,
          filename: "scanarr_library_#{Time.current.strftime('%Y%m%d')}.scanarr",
          type: "application/gzip"
      end
    end
  end
end
```

**Example usage with curl:**

```bash
# Create a backup
curl -X POST http://localhost:3000/api/v1/backups \
  -u admin:password \
  -H "Content-Type: application/json"

# List backups
curl http://localhost:3000/api/v1/backups \
  -u admin:password

# Download latest backup
curl -o backup.zip http://localhost:3000/api/v1/backups/1/download \
  -u admin:password

# Export library
curl -o library.scanarr http://localhost:3000/api/v1/exports/library \
  -u admin:password
```

---

## 8. Implementation Plan

### Phase 1: Database Backups (Core) -- 3-5 days

**Goal**: Automated PostgreSQL backups with retention, accessible via admin UI and API.

1. **Migration**: Create `backup_records` table
2. **Service**: `Backup::DatabaseBackupService` -- pg_dump + zip creation
3. **Service**: `Backup::IntegrityChecker` -- validate backup files
4. **Job**: `ScheduledBackupJob` -- runs on SolidQueue recurring schedule
5. **Job**: `BackupRetentionCleanupJob` -- enforces retention policy
6. **Controller**: `Admin::BackupsController` -- index, create, download, destroy
7. **View**: Admin backup management page
8. **Rake tasks**: `scanarr:backup:create`, `scanarr:backup:list`, `scanarr:backup:verify`
9. **Config**: Add to `config/recurring.yml`
10. **Tests**: Service unit tests, job tests, controller integration tests

**Milestone**: A user can create, download, and restore database backups from the admin UI. Backups run automatically every night with retention cleanup.

### Phase 2: Library Export/Import -- 3-5 days

**Goal**: Portable `.scanarr` library export that can be imported into another instance.

1. **Service**: `LibraryExportService` -- generates `.scanarr` file
2. **Service**: `LibraryImportService` -- parses and imports with merge/overwrite/skip strategy
3. **Controller actions**: `export_library`, `import_library` on backups controller
4. **UI**: Export button + import form with strategy selector on admin page
5. **Rake tasks**: `scanarr:export:library`, `scanarr:export:import`
6. **API**: `GET /api/v1/exports/library`, `POST /api/v1/imports/library`
7. **Tests**: Round-trip export/import test, merge strategy tests, conflict resolution tests

**Milestone**: A user can export their entire library, spin up a fresh Scanarr instance, and import the file to replicate their setup.

### Phase 3: Mihon Import -- 2-3 days

**Goal**: Import a Mihon/Tachiyomi `.tachibk` backup into Scanarr.

1. **Dependency**: Add `google-protobuf` gem
2. **Proto schema**: Generate Ruby classes from Mihon's backup protobuf schema
3. **Mapping**: `Mihon::SOURCE_MAP` -- numeric source ID to Scanarr source key
4. **Service**: `Mihon::ImportService` -- parse tachibk, map sources, import data
5. **UI**: "Import from Mihon" button on admin backups page
6. **Docs**: Document which Mihon sources are supported, how to find source IDs

**Milestone**: A Mihon user can import their library into Scanarr, getting their series list, reading progress, and follows (for supported sources).

### Phase 4: Settings Export/Import + Cloud Destinations -- 2-3 days

**Goal**: Lightweight settings portability and off-site backup storage.

1. **Service**: `SettingsExportService`, `SettingsImportService`
2. **Destination abstraction**: `Backup::Destinations::Base`, `::Local`, `::S3`
3. **Config**: `config/backup.yml` for backup destination configuration
4. **UI**: Settings export/import buttons, backup destination configuration
5. **S3 support**: Add `aws-sdk-s3` gem (optional dependency)

**Milestone**: Users can export/import app settings separately. Users with S3/B2 can have backups automatically synced to cloud storage.

### Phase 5: Restore Service + Safety -- 1-2 days

**Goal**: Full database restore with safety guarantees.

1. **Service**: `Backup::DatabaseRestoreService` -- pg restore with safety backup
2. **UI**: Restore button with confirmation dialog and dry-run preview
3. **Rake task**: `scanarr:backup:restore[path]` with interactive confirmation
4. **Safety**: Auto-create pre-restore backup, dry-run mode

**Milestone**: Complete backup lifecycle: create, verify, download, restore.

### Total Estimated Effort: 11-18 days

### Dependencies to Add

```ruby
# Gemfile additions (phased):

# Phase 1: Already have rubyzip
# gem "rubyzip" (already present)

# Phase 3: Mihon protobuf parsing
gem "google-protobuf", "~> 4.0"

# Phase 4: Cloud storage (optional)
gem "aws-sdk-s3", "~> 1.0", require: false
```

### File Structure

```
app/
  controllers/
    admin/
      backups_controller.rb        # Phase 1-4
    api/
      v1/
        backups_controller.rb      # Phase 1-2
  jobs/
    scheduled_backup_job.rb        # Phase 1
    backup_retention_cleanup_job.rb # Phase 1
  models/
    backup_record.rb               # Phase 1
  services/
    backup/
      database_backup_service.rb   # Phase 1
      database_restore_service.rb  # Phase 5
      integrity_checker.rb         # Phase 1
      destinations/
        base.rb                    # Phase 4
        local.rb                   # Phase 4
        s3.rb                      # Phase 4
    library_export_service.rb      # Phase 2
    library_import_service.rb      # Phase 2
    settings_export_service.rb     # Phase 4
    settings_import_service.rb     # Phase 4
    mihon/
      import_service.rb            # Phase 3
      source_mapping.rb            # Phase 3
  views/
    admin/
      backups/
        index.html.erb             # Phase 1
        _backup_row.html.erb       # Phase 1
config/
  backup.yml                       # Phase 1
db/
  migrate/
    XXXXXXXX_create_backup_records.rb # Phase 1
lib/
  tasks/
    backup.rake                    # Phase 1-2
  mihon/
    backup_pb.rb                   # Phase 3 (generated protobuf)
```

---

## Appendix A: PostgreSQL Backup Considerations

### Why Not `pg_basebackup`?

For Scanarr's scale (single-user self-hosted app), `pg_dump` is the right choice:

- `pg_dump` produces logical backups (SQL) that are portable across PostgreSQL versions
- `pg_basebackup` creates physical backups of the entire cluster -- overkill for our use case
- `pg_dump` can be run while the database is in use with no locking
- Logical backups are easier to inspect and debug
- Size is much smaller since we only dump the relevant database (not system catalogs)

### Backup During Active Use

PostgreSQL's MVCC ensures `pg_dump` creates a consistent snapshot even while the app is serving requests. No need to stop the server or pause SolidQueue.

### Point-in-Time Recovery (PITR)

For advanced users who want continuous protection:

- Enable WAL archiving in `postgresql.conf` (`archive_mode = on`)
- Use a tool like pgBackRest or WAL-G for continuous WAL archiving
- Combine with Scanarr's daily `pg_dump` backups for belt-and-suspenders protection

This is outside Scanarr's scope but worth documenting for power users.

## Appendix B: Mihon Source ID Discovery

To find the Mihon source ID for a given source:

1. Open a Mihon backup in the [Tachibk Viewer](https://backup.mihon.tools/)
2. Look at the `backupSources` array -- each entry has `name` and `sourceId`
3. Alternatively, look at the Mihon extension source code: the source ID is `hashCode()` of the extension's fully qualified class name

Community tools like [tachiyomi-backup-models](https://github.com/ClementD64/tachiyomi-backup-models) can help extract and document these mappings.

## Appendix C: Comparison Matrix

| Feature | Sonarr | Kavita | Komga | Mihon | Scanarr (Proposed) |
|---------|--------|--------|-------|-------|-------------------|
| Auto backup | Yes (scheduled) | Yes (nightly) | No | Yes (configurable) | Yes (SolidQueue) |
| Backup format | ZIP (SQLite + config) | ZIP (SQLite + config) | N/A | .tachibk (protobuf+gz) | ZIP (pg_dump + config) |
| Cloud backup | No (3rd party tools) | No | N/A | No (use FolderSync) | Yes (S3/B2) |
| Library export | No | No | No | Yes (full library) | Yes (.scanarr) |
| Cross-instance import | No | No | No | Yes (fork-compatible) | Yes |
| Import from Mihon | N/A | N/A | N/A | N/A | Yes (Phase 3) |
| Backup API | Yes (/api/v3/system/backup) | No | No | N/A (mobile app) | Yes (/api/v1/backups) |
| Retention policy | Yes (count-based) | Yes (count-based) | N/A | N/A | Yes (daily/weekly/monthly) |
| Integrity check | No | No | N/A | N/A | Yes (checksum + structure) |
| Dry-run import | No | No | N/A | No | Yes |
| Merge strategies | N/A | N/A | N/A | Basic (overwrite/skip) | Yes (merge/overwrite/skip) |

---

## References

- [Mihon Backup Guide](https://mihon.app/docs/guides/backups) -- Official documentation for Mihon's backup system
- [Tachiyomi Backup Protobuf Schema](https://gist.github.com/intrnl/f7ced6833ca6a1d353dd8742c7917db5) -- Community-maintained protobuf schema
- [Tachiyomi Backup Format & JSON Conversion](https://phobos.gitgud.site/posts/tachiyomi-backup-to-json/) -- Detailed format analysis
- [tachiyomi-backup-models](https://github.com/ClementD64/tachiyomi-backup-models) -- NPM library for parsing Tachiyomi backups
- [Mihon Backup Viewer](https://backup.mihon.tools/) -- Web tool for inspecting .tachibk files
- [Sonarr System/Backup Documentation](https://wiki.servarr.com/sonarr/system) -- Servarr Wiki
- [Sonarr Backup & Restore](https://nzbdrone.readthedocs.io/Backup-and-Restore/) -- Legacy NzbDrone docs on backup contents
- [Kavita Backup Discussion](https://github.com/Kareadita/Kavita/discussions/3016) -- Community discussion on restore process
- [Kavita Backup Issues](https://github.com/Kareadita/Kavita/issues/3456) -- Known issues with backup not including database
- [Komga Database Backup Request](https://github.com/gotson/komga/issues/570) -- Feature request for Komga backups
- [PostgreSQL Backup & Restore Documentation](https://www.postgresql.org/docs/current/backup.html) -- Official PostgreSQL backup guide
- [PostgreSQL Continuous Archiving (PITR)](https://www.postgresql.org/docs/current/continuous-archiving.html)
- [Mihon BackupManga Source](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/BackupManga.kt) -- Kotlin data class with protobuf annotations
