class LibraryImportService
  SUPPORTED_VERSIONS = [ 1 ].freeze

  Result = Data.define(:success, :imported, :skipped, :errors)

  def initialize(data:, user:, strategy: :merge)
    @data = data
    @user = user
    @strategy = strategy
    @imported = { library_series: 0, series: 0, chapters: 0, progress: 0, follows: 0 }
    @skipped = { library_series: 0, series: 0, chapters: 0, progress: 0, follows: 0 }
    @errors = []
  end

  def perform
    parsed = parse_data

    ActiveRecord::Base.transaction do
      import_library_series(parsed["library_series"])
      import_reading_progress(parsed["reading_progress"])
      import_follows(parsed["follows"])
    end

    Result.new(success: @errors.empty?, imported: @imported, skipped: @skipped, errors: @errors)
  rescue => e
    @errors << e.message
    Result.new(success: false, imported: @imported, skipped: @skipped, errors: @errors)
  end

  private

  def parse_data
    raw = if @data.is_a?(String) && @data.start_with?("\x1f\x8b".b)
      Zlib::GzipReader.new(StringIO.new(@data)).read
    elsif @data.is_a?(String)
      @data
    else
      raise "Unsupported import data format"
    end

    parsed = JSON.parse(raw)

    unless parsed["format"] == "scanarr_library_export"
      raise "Unknown export format: #{parsed['format']}"
    end

    unless SUPPORTED_VERSIONS.include?(parsed["version"])
      raise "Unsupported export version: #{parsed['version']}"
    end

    parsed
  end

  def import_library_series(library_series_data)
    return unless library_series_data

    library_series_data.each do |ls_data|
      ls = LibrarySeries.find_or_initialize_by(canonical_title: ls_data["canonical_title"])

      if ls.persisted? && @strategy == :skip
        @skipped[:library_series] += 1
        next
      end

      ls.assign_attributes(
        status: ls_data["status"] || "ongoing",
        anilist_id: ls_data["anilist_id"],
        mal_id: ls_data["mal_id"],
        mangadex_id: ls_data["mangadex_id"]
      )
      ls.save!
      @imported[:library_series] += 1

      (ls_data["series"] || []).each do |series_data|
        import_series(ls, series_data)
      end
    rescue => e
      @errors << "LibrarySeries '#{ls_data['canonical_title']}': #{e.message}"
    end
  end

  def import_series(library_series, series_data)
    # Find existing series by title under this library_series
    series = library_series.series.find_or_initialize_by(
      canonical_title: series_data["canonical_title"]
    )

    if series.persisted? && @strategy == :skip
      @skipped[:series] += 1
      return
    end

    series.assign_attributes(
      cover_url: series_data["cover_url"],
      author_name: series_data["author_name"],
      artist_name: series_data["artist_name"],
      description: series_data["description"],
      status: series_data["status"],
      series_type: series_data["series_type"],
      reading_style: series_data["reading_style"],
      language_policy: series_data["language_policy"],
      raw_tags: series_data["raw_tags"],
      normalized_categories: series_data["normalized_categories"],
      alt_titles: series_data["alt_titles"],
      localized_title: series_data["localized_title"]
    )
    series.save!
    @imported[:series] += 1

    # Import source mappings
    (series_data["source_mappings"] || []).each do |mapping|
      source = Source.find_by(key: mapping["source_key"])
      next unless source

      ss = SeriesSource.find_or_initialize_by(series: series, source: source)
      ss.assign_attributes(
        source_series_id: mapping["source_series_id"],
        library_base_path: mapping["library_base_path"]
      )
      ss.save!
    end

    # Import chapters
    (series_data["chapters"] || []).each do |ch_data|
      import_chapter(series, ch_data)
    end
  end

  def import_chapter(series, ch_data)
    chapter = series.chapters.find_or_initialize_by(
      chapter_number: ch_data["chapter_number"],
      language: ch_data["language"],
      group: ch_data["group"]
    )

    if chapter.persisted? && @strategy == :skip
      @skipped[:chapters] += 1
      return
    end

    source = Source.find_by(key: ch_data["source_key"]) if ch_data["source_key"]

    chapter.assign_attributes(
      title: ch_data["title"],
      source_url: ch_data["source_url"],
      source: source,
      published_at: ch_data["published_at"]
    )
    chapter.save!
    @imported[:chapters] += 1
  end

  def import_reading_progress(progress_data)
    return unless progress_data

    progress_data.each do |pg_data|
      series = Series.find_by(canonical_title: pg_data["series_title"])
      next unless series

      chapter = series.chapters.find_by(chapter_number: pg_data["chapter_number"])
      next unless chapter

      progress = ChapterProgress.find_or_initialize_by(user: @user, chapter: chapter)

      if progress.persisted? && @strategy == :skip
        @skipped[:progress] += 1
        next
      end

      # For merge strategy, keep whichever is newer
      if progress.persisted? && @strategy == :merge
        import_time = Time.zone.parse(pg_data["progressed_at"]) rescue nil
        if import_time && progress.progressed_at && import_time <= progress.progressed_at
          @skipped[:progress] += 1
          next
        end
      end

      progress.assign_attributes(
        page_index: pg_data["page_index"],
        page_count: pg_data["page_count"],
        status: pg_data["status"],
        progressed_at: pg_data["progressed_at"]
      )
      progress.save!
      @imported[:progress] += 1
    rescue => e
      @errors << "Progress '#{pg_data['series_title']}' ch#{pg_data['chapter_number']}: #{e.message}"
    end
  end

  def import_follows(follows_data)
    return unless follows_data

    follows_data.each do |follow_data|
      ls = LibrarySeries.find_by(canonical_title: follow_data["series_title"])
      next unless ls

      follow = UserSeriesFollow.find_or_initialize_by(user: @user, library_series: ls)

      if follow.persisted? && @strategy == :skip
        @skipped[:follows] += 1
        next
      end

      follow.assign_attributes(
        download_policy: follow_data["download_policy"] || "notify_only",
        check_interval_minutes: follow_data["check_interval_minutes"],
        source_priority: follow_data["source_priority"]
      )
      follow.save!
      @imported[:follows] += 1
    rescue => e
      @errors << "Follow '#{follow_data['series_title']}': #{e.message}"
    end
  end
end
