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
      sources: export_sources,
      library_series: export_library_series,
      reading_progress: export_reading_progress,
      follows: export_follows
    }

    compressed = StringIO.new
    Zlib::GzipWriter.wrap(compressed) do |gz|
      gz.write(JSON.generate(export_data))
    end

    compressed.string
  end

  # Returns the uncompressed JSON hash (for preview/dry-run)
  def preview
    {
      sources: Source.count,
      library_series: LibrarySeries.count,
      series: Series.count,
      chapters: Chapter.count,
      reading_progress: @user.chapter_progresses.count,
      follows: @user.user_series_follows.count
    }
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
      series: [ :sources, :series_sources, { chapters: [ :volume, :source ] } ]
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
        check_interval_minutes: follow.check_interval_minutes,
        source_priority: follow.source_priority
      }
    end
  end
end
