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
      return result unless @errors.empty?

      check_zip_integrity
      return result unless @errors.empty?

      check_manifest
      check_database_dump

      result
    end

    private

    def result
      Result.new(valid: @errors.empty?, errors: @errors, warnings: @warnings)
    end

    def check_file_exists
      @errors << "Backup file does not exist" unless @backup_path.exist?
    end

    def check_zip_integrity
      Zip::File.open(@backup_path) do |zip|
        zip.each do |entry|
          entry.get_input_stream { |io| io.read }
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

        content = ""
        Zlib::GzipReader.new(StringIO.new(zip.read(entry))) do |gz|
          content = gz.read(1024)
        end

        unless content.include?("PostgreSQL") || content.include?("pg_dump")
          @warnings << "database.sql.gz does not appear to be a PostgreSQL dump"
        end
      end
    rescue Zlib::GzipFile::Error
      @errors << "database.sql.gz is not valid gzip"
    end
  end
end
