namespace :scanarr do
  namespace :backup do
    desc "Create a full database backup"
    task create: :environment do
      puts "Creating backup..."
      service = Backup::DatabaseBackupService.new
      result = service.perform

      BackupRecord.create!(
        filename: File.basename(result.path),
        path: result.path.to_s,
        size: result.size,
        checksum: result.checksum,
        backup_type: "manual",
        status: "complete"
      )

      puts "Backup created: #{result.path}"
      puts "Size: #{ActiveSupport::NumberHelper.number_to_human_size(result.size)}"
      puts "Checksum: sha256:#{result.checksum}"
    end

    desc "List all backups"
    task list: :environment do
      backups = BackupRecord.order(created_at: :desc)
      if backups.empty?
        puts "No backups found."
      else
        backups.each do |b|
          size = b.size ? ActiveSupport::NumberHelper.number_to_human_size(b.size) : "unknown"
          exists = b.file_exists? ? "OK" : "MISSING"
          puts "#{b.created_at.strftime('%Y-%m-%d %H:%M')}  #{b.backup_type.ljust(12)}  #{b.status.ljust(8)}  #{size.ljust(10)}  #{exists.ljust(7)}  #{b.filename}"
        end
      end
    end

    desc "Verify a backup file's integrity: rake scanarr:backup:verify[/path/to/backup.zip]"
    task :verify, [ :path ] => :environment do |_t, args|
      path = args[:path]
      abort "Usage: rake scanarr:backup:verify[/path/to/backup.zip]" unless path
      abort "File not found: #{path}" unless File.exist?(path)

      puts "Verifying backup: #{path}"
      result = Backup::IntegrityChecker.new(backup_path: path).check
      if result.valid
        puts "Backup is valid."
        result.warnings.each { |w| puts "  WARNING: #{w}" }
      else
        puts "Backup is INVALID:"
        result.errors.each { |e| puts "  ERROR: #{e}" }
        result.warnings.each { |w| puts "  WARNING: #{w}" }
        exit 1
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
    desc "Export library to .scanarr file: rake scanarr:export:library[output_path]"
    task :library, [ :output ] => :environment do |_t, args|
      output = args[:output] || "scanarr_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.scanarr"
      user = User.first || abort("No user found")

      preview = LibraryExportService.new(user: user).preview
      puts "Exporting: #{preview[:sources]} sources, #{preview[:library_series]} library series, #{preview[:chapters]} chapters, #{preview[:reading_progress]} reading progress, #{preview[:follows]} follows"

      data = LibraryExportService.new(user: user).perform
      File.binwrite(output, data)
      puts "Export saved to: #{output}"
      puts "Size: #{ActiveSupport::NumberHelper.number_to_human_size(File.size(output))}"
    end

    desc "Import library from .scanarr file: rake scanarr:export:import[path,strategy]"
    task :import, [ :path, :strategy ] => :environment do |_t, args|
      path = args[:path]
      abort "Usage: rake scanarr:export:import[/path/to/export.scanarr,merge|overwrite|skip]" unless path
      abort "File not found: #{path}" unless File.exist?(path)

      strategy = (args[:strategy] || "merge").to_sym
      unless %i[merge overwrite skip].include?(strategy)
        abort "Invalid strategy: #{strategy}. Use merge, overwrite, or skip."
      end

      user = User.first || abort("No user found")
      data = File.binread(path)

      puts "Importing with strategy: #{strategy}..."
      result = LibraryImportService.new(data: data, user: user, strategy: strategy).perform

      if result.success
        puts "Import complete!"
        puts "Imported: #{result.imported.inspect}"
        puts "Skipped: #{result.skipped.inspect}"
      else
        puts "Import completed with errors:"
        result.errors.each { |e| puts "  ERROR: #{e}" }
        puts "Imported: #{result.imported.inspect}"
        puts "Skipped: #{result.skipped.inspect}"
        exit 1
      end
    end
  end
end
