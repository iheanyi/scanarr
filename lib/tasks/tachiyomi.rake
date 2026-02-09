# frozen_string_literal: true

namespace :scanarr do
  namespace :tachiyomi do
    desc "Import a Mihon/Tachiyomi backup: rake scanarr:tachiyomi:import[file,username,strategy]"
    task :import, [ :file, :username, :strategy ] => :environment do |_t, args|
      file_path = args[:file] || abort("Usage: rake scanarr:tachiyomi:import[file.tachibk,username,merge]")
      username = args[:username] || abort("Username required")
      strategy = (args[:strategy] || "merge").to_sym

      abort("File not found: #{file_path}") unless File.exist?(file_path)

      user = User.find_by!(username: username)

      # Always show preview first
      puts "Parsing #{file_path}..."
      preview = TachiyomiImportService.new(user: user, file: file_path, strategy: strategy).preview

      puts "\n=== Import Preview ==="
      puts "Total manga in backup: #{preview[:total_manga]}"
      puts "  Mapped (will import): #{preview[:mapped_manga]}"
      puts "  Unmapped (will skip): #{preview[:unmapped_manga]}"
      puts "Total chapters: #{preview[:total_chapters]}"
      puts "Read chapters: #{preview[:read_chapters]}"
      puts "History entries: #{preview[:total_history]}"
      puts "Tracking entries: #{preview[:total_tracking]}"

      if preview[:unmapped_sources].any?
        puts "\nUnmapped sources (#{preview[:unmapped_sources].size}):"
        preview[:unmapped_sources].each { |s| puts "  - #{s[:name]} (ID: #{s[:id]})" }
      end

      puts "\nMapped sources:"
      preview[:sources].select { |s| s[:mapped] }.each { |s| puts "  + #{s[:name]}" }

      # Ask for confirmation (skip with CONFIRM=y)
      unless ENV["CONFIRM"] == "y"
        print "\nProceed with import for user '#{username}' using strategy '#{strategy}'? [y/N] "
        answer = $stdin.gets&.strip&.downcase
        abort("Import cancelled.") unless answer == "y"
      end

      puts "\nImporting..."
      result = TachiyomiImportService.new(user: user, file: file_path, strategy: strategy).perform

      if result.success
        puts "\nImport complete!"
        result.imported.each { |k, v| puts "  #{k}: #{v}" }
      else
        puts "\nImport had errors:"
        result.errors.each { |e| puts "  - #{e}" }
        puts "\nPartial import results:"
        result.imported.each { |k, v| puts "  #{k}: #{v}" }
      end
    end

    desc "Export library as Mihon/Tachiyomi backup: rake scanarr:tachiyomi:export[username,output_path]"
    task :export, [ :username, :output_path ] => :environment do |_t, args|
      username = args[:username] || abort("Usage: rake scanarr:tachiyomi:export[username,output.tachibk]")
      output_path = args[:output_path] || "scanarr_#{Time.current.strftime('%Y-%m-%d_%H-%M')}.tachibk"

      user = User.find_by!(username: username)
      puts "Exporting library for user '#{username}'..."

      data = TachiyomiExportService.new(user: user).perform
      File.binwrite(output_path, data)

      puts "Exported to #{output_path} (#{(data.bytesize / 1024.0).round(1)} KB)"
    end

    desc "Inspect a Mihon/Tachiyomi backup: rake scanarr:tachiyomi:inspect[file]"
    task :inspect, [ :file ] => :environment do |_t, args|
      file_path = args[:file] || abort("Usage: rake scanarr:tachiyomi:inspect[backup.tachibk]")
      abort("File not found: #{file_path}") unless File.exist?(file_path)

      require_relative "../../lib/tachiyomi/parser"

      puts "Parsing #{file_path}..."
      backup = Tachiyomi::Parser.new.parse(file_path)

      puts "\n=== Backup Summary ==="
      puts "Manga: #{backup.backupManga.size}"
      puts "Categories: #{backup.backupCategories.size}"
      puts "Sources: #{backup.backupSources.size}"

      total_chapters = backup.backupManga.sum { |m| m.chapters.size }
      read_chapters = backup.backupManga.sum { |m| m.chapters.count(&:read) }
      total_history = backup.backupManga.sum { |m| m.history.size }
      total_tracking = backup.backupManga.sum { |m| m.tracking.size }

      puts "Total chapters: #{total_chapters}"
      puts "Read chapters: #{read_chapters}"
      puts "History entries: #{total_history}"
      puts "Tracking entries: #{total_tracking}"

      puts "\n=== Sources ==="
      backup.backupSources.sort_by(&:name).each do |source|
        mapped = TachiyomiSourceMapper.scanarr_key_for(source.sourceId)
        manga_count = backup.backupManga.count { |m| m.source == source.sourceId }
        status = mapped ? "-> #{mapped}" : "UNMAPPED"
        puts "  #{source.name} (#{source.sourceId}): #{manga_count} manga [#{status}]"
      end

      unmapped = TachiyomiSourceMapper.unmapped_sources(backup)
      if unmapped.any?
        puts "\n=== Unmapped Source IDs ==="
        unmapped.each do |id|
          name = TachiyomiSourceMapper.source_name_from_backup(backup, id) || "Unknown"
          future = TachiyomiSourceMapper.future_source_name(id)
          label = future ? " (known as: #{future})" : ""
          puts "  #{id}: #{name}#{label}"
        end
      end

      puts "\n=== Top Manga (by chapters) ==="
      backup.backupManga
        .sort_by { |m| -m.chapters.size }
        .first(10)
        .each do |manga|
          source_name = backup.backupSources.find { |s| s.sourceId == manga.source }&.name || "?"
          puts "  #{manga.title} (#{manga.chapters.size} ch, source: #{source_name})"
        end
    end
  end
end
