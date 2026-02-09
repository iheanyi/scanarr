# frozen_string_literal: true

require_relative "../../lib/tachiyomi/parser"

class TachiyomiExportService
  def initialize(user:)
    @user = user
  end

  def perform
    backup = Tachiyomi::Backup.new(
      backupManga: build_manga_list,
      backupCategories: [],
      backupSources: build_source_list
    )

    encoded = Tachiyomi::Backup.encode(backup)
    Zlib.gzip(encoded)
  end

  # Return stats without generating the full backup (SQL-only, no eager loading)
  def preview
    exportable_keys = YAML.load_file(Rails.root.join("config", "tachiyomi_source_map.yml"))["export_ids"].keys
    followed_ls_ids = @user.user_series_follows.select(:library_series_id)

    exportable_series_ids = Series
      .where(library_series_id: followed_ls_ids)
      .joins(:sources)
      .where(sources: { key: exportable_keys })
      .distinct
      .pluck(:id)

    chapter_count = Chapter.where(series_id: exportable_series_ids).count

    source_keys = Source.joins(:series_sources)
      .where(series_sources: { series_id: exportable_series_ids })
      .where(key: exportable_keys)
      .distinct
      .pluck(:key)

    {
      series: exportable_series_ids.size,
      chapters: chapter_count,
      sources: source_keys.size,
      source_names: Source.where(key: source_keys).pluck(:name)
    }
  end

  private

  def load_follows
    @user.user_series_follows.includes(
      library_series: {
        series: [
          :sources,
          :series_sources,
          { chapters: :chapter_progresses }
        ]
      }
    )
  end

  def build_manga_list
    @source_ids_used = Set.new
    manga_list = []

    load_follows.find_each do |follow|
      ls = follow.library_series
      next unless ls

      ls.series.each do |series|
        manga = build_manga(series, follow)
        next unless manga

        manga_list << manga
      end
    end

    manga_list
  end

  def build_manga(series, follow)
    source = series.primary_source
    return nil unless source

    tachi_id = TachiyomiSourceMapper.tachiyomi_id_for(source.key)
    return nil unless tachi_id

    @source_ids_used.add(tachi_id)

    series_source = series.series_sources.find { |ss| ss.source_id == source.id }

    Tachiyomi::BackupManga.new(
      source: tachi_id,
      url: series_source&.source_series_id || "",
      title: series.canonical_title,
      artist: series.artist_name || "",
      author: series.author_name || "",
      description: series.description || "",
      genre: series.normalized_categories || [],
      status: scanarr_to_tachi_status(series.status),
      thumbnailUrl: series.cover_image_url || "",
      dateAdded: epoch_millis(follow.created_at),
      favorite: true,
      chapters: build_chapters(series),
      history: build_history(series),
      tracking: build_tracking(series)
    )
  end

  def build_chapters(series)
    series.chapters.map do |ch|
      progress = ch.chapter_progresses.find { |cp| cp.user_id == @user.id }

      Tachiyomi::BackupChapter.new(
        url: ch.source_url || "",
        name: ch.title || "Chapter #{ch.chapter_number}",
        scanlator: ch.group || "",
        chapterNumber: ch.chapter_number_value&.to_f || 0.0,
        read: progress&.status == "completed",
        lastPageRead: progress&.page_index&.to_i || 0,
        dateUpload: epoch_millis(ch.published_at),
        dateFetch: epoch_millis(ch.created_at),
        sourceOrder: 0
      )
    end
  end

  def build_history(series)
    series.chapters.filter_map do |ch|
      progress = ch.chapter_progresses.find { |cp| cp.user_id == @user.id }
      next unless progress&.progressed_at

      Tachiyomi::BackupHistory.new(
        url: ch.source_url || "",
        lastRead: epoch_millis(progress.progressed_at),
        readDuration: 0
      )
    end
  end

  def build_tracking(series)
    ls = series.library_series
    return [] unless ls

    tracks = []
    if ls.anilist_id
      tracks << Tachiyomi::BackupTracking.new(
        syncId: 2,
        mediaId: ls.anilist_id.to_i,
        title: series.canonical_title
      )
    end
    if ls.mal_id
      tracks << Tachiyomi::BackupTracking.new(
        syncId: 1,
        mediaId: ls.mal_id.to_i,
        title: series.canonical_title
      )
    end
    tracks
  end

  def build_source_list
    export_keys = YAML.load_file(Rails.root.join("config", "tachiyomi_source_map.yml"))["export_ids"].keys

    Source.where(key: export_keys).filter_map do |source|
      tachi_id = TachiyomiSourceMapper.tachiyomi_id_for(source.key)
      next unless tachi_id && @source_ids_used&.include?(tachi_id)

      Tachiyomi::BackupSource.new(name: source.name, sourceId: tachi_id)
    end
  end

  def scanarr_to_tachi_status(status)
    case status&.downcase
    when "ongoing" then 1
    when "completed" then 2
    when "licensed" then 3
    when "publishing_finished" then 4
    when "hiatus" then 6
    when "cancelled" then 5
    else 0
    end
  end

  def epoch_millis(time)
    return 0 unless time
    (time.to_f * 1000).to_i
  end
end
