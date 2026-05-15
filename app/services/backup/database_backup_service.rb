require "zip"

module Backup
  class DatabaseBackupService
    Result = Data.define(:path, :size, :checksum, :manifest)

    def self.backup_dir
      Scanarr::Storage.backup_root
    end

    def initialize(destination: self.class.backup_dir, include_config: true)
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

        dump_database(tmpdir.join("database.sql.gz"))
        export_blob_metadata(tmpdir.join("active_storage_blobs.json"))

        if @include_config
          copy_config(tmpdir.join("config"))
        end

        manifest = generate_manifest(tmpdir)
        File.write(tmpdir.join("manifest.json"), JSON.pretty_generate(manifest))

        create_zip(tmpdir, zip_path)
      end

      checksum = Digest::SHA256.file(zip_path).hexdigest

      Result.new(
        path: zip_path,
        size: File.size(zip_path),
        checksum: checksum,
        manifest: {}
      )
    end

    private

    def dump_database(output_path)
      require "open3"

      db_config = ActiveRecord::Base.connection_db_config.configuration_hash

      cmd = [
        pg_dump_path,
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

      stdout, stderr, status = Open3.capture3(env, *cmd)

      raise "pg_dump failed: #{stderr.last(500)}" unless status.success?

      Zlib::GzipWriter.open(output_path.to_s) do |gz|
        gz.write(stdout)
      end
    end

    # Find pg_dump binary matching the server version.
    # Falls back to the default pg_dump in PATH.
    def pg_dump_path
      server_version = ActiveRecord::Base.connection.select_value("SHOW server_version").to_i
      versioned_path = "/opt/homebrew/opt/postgresql@#{server_version}/bin/pg_dump"
      return versioned_path if File.executable?(versioned_path)

      "pg_dump"
    end

    def export_blob_metadata(output_path)
      blobs = ActiveStorage::Blob.find_each.map do |blob|
        {
          key: blob.key,
          filename: blob.filename.to_s,
          content_type: blob.content_type,
          byte_size: blob.byte_size,
          checksum: blob.checksum,
          service_name: blob.service_name,
          created_at: blob.created_at.iso8601,
          attachments: blob.attachments.map do |att|
            { record_type: att.record_type, record_id: att.record_id, name: att.name }
          end
        }
      end

      File.write(output_path, JSON.pretty_generate(blobs))
    end

    def copy_config(config_dir)
      FileUtils.mkdir_p(config_dir)

      # Copy storage.yml but sanitize credentials
      storage_path = Rails.root.join("config/storage.yml")
      if storage_path.exist?
        content = File.read(storage_path)
        sanitized = content.gsub(/(?<=secret_access_key:\s).+/, "[REDACTED]")
                           .gsub(/(?<=access_key_id:\s).+/, "[REDACTED]")
        File.write(config_dir.join("storage.yml"), sanitized)
      end
    end

    def generate_manifest(tmpdir)
      table_counts = {}
      safe_tables = %w[series chapters library_series users user_series_follows
                       chapter_progresses sources series_sources releases
                       file_assets pages volumes]

      safe_tables.each do |table|
        table_counts[table] = ActiveRecord::Base.connection.execute(
          "SELECT COUNT(*) FROM #{ActiveRecord::Base.connection.quote_table_name(table)}"
        ).first["count"]
      rescue ActiveRecord::StatementInvalid
        # Table may not exist yet
      end

      {
        version: 1,
        format: "scanarr_backup",
        created_at: Time.current.iso8601,
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
