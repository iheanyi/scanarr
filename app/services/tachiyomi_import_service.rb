# frozen_string_literal: true

require_relative "../../lib/tachiyomi/parser"

class TachiyomiImportService
  Result = Data.define(:success, :imported, :skipped, :unmapped_sources, :errors)

  def initialize(user:, file:, strategy: :merge)
    @user = user
    @file = file
    @strategy = strategy.to_sym
    @imported = { series: 0, chapters: 0, progress: 0, follows: 0, tracking: 0 }
    @skipped = { series: 0, chapters: 0, progress: 0 }
    @unmapped_sources = []
    @errors = []
  end

  def perform
    @backup = Tachiyomi::Parser.new.parse(@file)
    collect_unmapped_sources
    preload_sources

    total = @backup.backupManga.size
    @backup.backupManga.each_with_index do |manga, i|
      import_manga(manga)
      log_progress(i + 1, total) if (i + 1) % 50 == 0 || i + 1 == total
    end

    Result.new(
      success: @errors.empty?,
      imported: @imported,
      skipped: @skipped,
      unmapped_sources: @unmapped_sources,
      errors: @errors
    )
  rescue => e
    @errors << e.message
    Result.new(
      success: false,
      imported: @imported,
      skipped: @skipped,
      unmapped_sources: @unmapped_sources,
      errors: @errors
    )
  end

  # Parse without importing — return stats for preview
  def preview
    @backup = Tachiyomi::Parser.new.parse(@file)
    collect_unmapped_sources

    mapped_manga = @backup.backupManga.select { |m| TachiyomiSourceMapper.scanarr_key_for(m.source) }
    total_chapters = @backup.backupManga.sum { |m| m.chapters.size }
    read_chapters = @backup.backupManga.sum { |m| m.chapters.count(&:read) }
    total_history = @backup.backupManga.sum { |m| m.history.size }
    total_tracking = @backup.backupManga.sum { |m| m.tracking.size }

    {
      total_manga: @backup.backupManga.size,
      mapped_manga: mapped_manga.size,
      unmapped_manga: @backup.backupManga.size - mapped_manga.size,
      total_chapters: total_chapters,
      read_chapters: read_chapters,
      total_history: total_history,
      total_tracking: total_tracking,
      sources: @backup.backupSources.map { |s| { name: s.name, id: s.sourceId, mapped: TachiyomiSourceMapper.scanarr_key_for(s.sourceId).present? } },
      unmapped_sources: @unmapped_sources
    }
  end

  private

  def preload_sources
    @source_cache = Source.all.index_by(&:key)
  end

  def log_progress(current, total)
    $stdout.print "\r  [#{current}/#{total}] series: +#{@imported[:series]} chapters: +#{@imported[:chapters]} progress: +#{@imported[:progress]} errors: #{@errors.size}"
    $stdout.flush
    $stdout.puts if current == total
  end

  def collect_unmapped_sources
    unmapped_ids = TachiyomiSourceMapper.unmapped_sources(@backup)
    @unmapped_sources = unmapped_ids.map do |id|
      name = TachiyomiSourceMapper.source_name_from_backup(@backup, id) ||
             TachiyomiSourceMapper.future_source_name(id) ||
             "Unknown (#{id})"
      { id: id, name: name }
    end
  end

  def import_manga(manga)
    scanarr_key = TachiyomiSourceMapper.scanarr_key_for(manga.source)
    unless scanarr_key
      @skipped[:series] += 1
      return
    end

    source = @source_cache[scanarr_key]
    unless source
      @skipped[:series] += 1
      return
    end

    # Per-manga transaction so one failure doesn't roll back everything
    ActiveRecord::Base.transaction do
      series = find_or_create_series(manga, source)
      return unless series

      import_chapters_bulk(manga.chapters, series, source)
      import_history(manga.history, series)
      import_tracking(manga, series)
      create_follow(series, manga)
    end
  rescue => e
    @errors << "Manga '#{manga.title}': #{e.message}"
  end

  def find_or_create_series(manga, source)
    # Tier 1: Match by source_series_id (URL path from Tachiyomi)
    if manga.url.present?
      series_source = SeriesSource.find_by(source: source, source_series_id: manga.url)
      return series_source.series if series_source
    end

    # Tier 2: Match by author/artist + title
    author = manga.author.presence
    artist = manga.artist.presence
    dedupe_name = author || artist

    if dedupe_name.present?
      series = Series.where(canonical_title: manga.title)
                     .where("author_name = ? OR artist_name = ?", dedupe_name, dedupe_name)
                     .first
      if series
        ensure_series_source(series, source, manga.url)
        return series
      end
    end

    # Tier 3: Match by title alone
    series = Series.find_by(canonical_title: manga.title)
    if series
      ensure_series_source(series, source, manga.url)
      return series
    end

    # Create new series
    series = Series.create!(
      canonical_title: manga.title,
      author_name: author,
      artist_name: artist,
      description: manga.description.presence,
      cover_url: manga.thumbnailUrl.presence,
      status: tachi_to_scanarr_status(manga.status),
      normalized_categories: manga.genre.to_a
    )

    ensure_series_source(series, source, manga.url)
    @imported[:series] += 1
    series
  end

  def ensure_series_source(series, source, source_series_id)
    return unless source_series_id.present?

    ss = SeriesSource.find_or_initialize_by(series: series, source: source)
    ss.update!(source_series_id: source_series_id) if ss.source_series_id != source_series_id
  end

  def import_chapters_bulk(tachi_chapters, series, source)
    return if tachi_chapters.empty?

    # Prefetch existing chapters for fast lookup
    existing = series.chapters
      .pluck(:chapter_number, :language, :id)
      .each_with_object({}) { |(num, lang, id), h| h[[ num, lang ]] = id }

    now = Time.current
    new_chapters = []
    read_chapter_ids = []
    read_tachi_map = {}

    tachi_chapters.each do |tch|
      chapter_number = format_chapter_number(tch.chapterNumber)
      next if chapter_number.blank?

      language = "en"
      key = [ chapter_number, language ]

      if existing.key?(key)
        if tch.read
          read_chapter_ids << existing[key]
          read_tachi_map[existing[key]] = tch
        end
        @skipped[:chapters] += 1
      else
        # Generate public_id and chapter_number_value since insert_all skips callbacks
        numeric_str = chapter_number.to_s[/\d+(\.\d+)?/]
        new_chapters << {
          series_id: series.id,
          chapter_number: chapter_number,
          chapter_number_value: numeric_str ? BigDecimal(numeric_str) : nil,
          public_id: Chapter.generate_public_id,
          title: tch.name.presence,
          source_id: source.id,
          source_url: tch.url.presence,
          language: language,
          group: tch.scanlator.presence,
          published_at: tch.dateUpload > 0 ? Time.at(tch.dateUpload / 1000.0) : nil,
          created_at: now,
          updated_at: now,
          _tachi: tch # stash for progress tracking
        }
      end
    end

    # Bulk insert new chapters
    if new_chapters.any?
      insertable = new_chapters.map { |ch| ch.except(:_tachi) }

      # Insert in batches of 500
      insertable.each_slice(500) do |batch|
        Chapter.insert_all(batch)
      end
      @imported[:chapters] += new_chapters.size

      # Update counter cache for the series
      Series.reset_counters(series.id, :chapters)

      # Re-fetch the inserted chapter IDs for progress tracking
      new_chapter_keys = new_chapters.map { |ch| [ ch[:chapter_number], ch[:language] ] }
      inserted = series.chapters
        .where(chapter_number: new_chapter_keys.map(&:first), language: "en")
        .pluck(:chapter_number, :language, :id)
        .each_with_object({}) { |(num, lang, id), h| h[[ num, lang ]] = id }

      new_chapters.each do |ch|
        tch = ch[:_tachi]
        next unless tch.read
        chapter_id = inserted[[ ch[:chapter_number], ch[:language] ]]
        next unless chapter_id
        read_chapter_ids << chapter_id
        read_tachi_map[chapter_id] = tch
      end
    end

    # Bulk update progress for read chapters
    bulk_update_progress(read_chapter_ids, read_tachi_map) if read_chapter_ids.any?
  end

  def bulk_update_progress(chapter_ids, tachi_map)
    # Find already-existing progress records
    existing_progress = ChapterProgress
      .where(user: @user, chapter_id: chapter_ids)
      .index_by(&:chapter_id)

    now = Time.current
    new_progress = []

    chapter_ids.each do |chapter_id|
      tch = tachi_map[chapter_id]
      next unless tch

      existing = existing_progress[chapter_id]

      if existing
        if @strategy == :skip || (@strategy == :merge && existing.status == "completed")
          @skipped[:progress] += 1
          next
        end
      end

      new_progress << {
        user_id: @user.id,
        chapter_id: chapter_id,
        page_index: [ tch.lastPageRead.to_i, 0 ].max,
        page_count: [ tch.lastPageRead.to_i + 1, 1 ].max,
        status: tch.read ? "completed" : "in_progress",
        progressed_at: now,
        created_at: now,
        updated_at: now
      }
    end

    if new_progress.any?
      new_progress.each_slice(500) do |batch|
        ChapterProgress.upsert_all(
          batch,
          unique_by: %i[user_id chapter_id]
        )
      end
      @imported[:progress] += new_progress.size
    end
  end

  def import_history(history_entries, series)
    return if history_entries.empty?

    # Match history entries to chapters by URL
    chapter_by_url = series.chapters.where.not(source_url: nil).index_by(&:source_url)

    now = Time.current
    progress_updates = []

    history_entries.each do |entry|
      chapter = chapter_by_url[entry.url]
      next unless chapter
      next unless entry.lastRead > 0

      last_read_time = Time.at(entry.lastRead / 1000.0)

      progress_updates << {
        user_id: @user.id,
        chapter_id: chapter.id,
        page_index: 0,
        page_count: 1,
        status: "in_progress",
        progressed_at: last_read_time,
        created_at: now,
        updated_at: now
      }
    end

    # Upsert history-based progress (only if newer than existing)
    if progress_updates.any?
      progress_updates.each_slice(500) do |batch|
        ChapterProgress.upsert_all(
          batch,
          unique_by: %i[user_id chapter_id],
          update_only: [ :progressed_at ]
        )
      end
    end
  end

  def import_tracking(manga, series)
    ls = series.library_series
    return unless ls

    manga.tracking.each do |track|
      media_id = track.mediaId > 0 ? track.mediaId : track.mediaIdInt
      next unless media_id > 0

      case track.syncId
      when 1 # MyAnimeList
        if ls.mal_id.nil? || @strategy == :overwrite
          ls.update!(mal_id: media_id)
          @imported[:tracking] += 1
        end
      when 2 # AniList
        if ls.anilist_id.nil? || @strategy == :overwrite
          ls.update!(anilist_id: media_id)
          @imported[:tracking] += 1
        end
      end
    end
  end

  def create_follow(series, manga)
    ls = series.library_series || series.ensure_library_series!
    return unless ls

    follow = UserSeriesFollow.find_or_initialize_by(user: @user, library_series: ls)
    return if follow.persisted? && @strategy == :skip

    follow.download_policy ||= "notify_only"
    follow.save! if follow.new_record?
    @imported[:follows] += 1 if follow.previously_new_record?
  end

  def format_chapter_number(float_val)
    return nil if float_val.nil? || float_val <= 0

    # Convert float like 1.0 to "1", 1.5 to "1.5"
    if float_val == float_val.to_i.to_f
      float_val.to_i.to_s
    else
      float_val.to_s
    end
  end

  def tachi_to_scanarr_status(tachi_status)
    case tachi_status
    when 1 then "ongoing"
    when 2 then "completed"
    when 3 then "licensed"   # officially licensed
    when 4 then "publishing_finished"
    when 5 then "cancelled"
    when 6 then "hiatus"
    else "unknown"
    end
  end
end
