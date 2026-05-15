class SeriesImporter
  def initialize(source:, adapter:)
    @source = source
    @adapter = adapter
  end

  def import!(series_url)
    series_result = @adapter.series(series_url)
    chapters = @adapter.chapters(series_result.url)
    normalizer = SeriesCategoryNormalizer.new
    normalized = normalizer.normalize_with_style(tags: series_result.tags, series_type: series_result.series_type)
    author_name = series_result.author.presence
    artist_name = series_result.artist.presence
    dedupe_name = author_name || artist_name

    series_source = SeriesSource.find_by(source: @source, source_series_id: series_result.id)
    series = series_source&.series

    if series.nil? && dedupe_name.present?
      series = Series.where(canonical_title: series_result.title)
                     .where("author_name = ? OR artist_name = ?", dedupe_name, dedupe_name)
                     .first
    end

    series ||= Series.find_by(canonical_title: series_result.title)
    series ||= Series.create!(
      canonical_title: series_result.title,
      author_name: author_name,
      artist_name: artist_name,
      cover_url: series_result.cover_url,
      description: series_result.description
    )

    series_source = SeriesSource.find_or_create_by!(series: series, source: @source)
    if series_result.id.present? && series_source.source_series_id != series_result.id
      series_source.update!(source_series_id: series_result.id)
    end

    updates = {
      raw_tags: Array(series_result.tags).compact,
      normalized_categories: normalized.fetch(:categories, []),
      reading_style: normalized.fetch(:reading_style, "left_to_right")
    }
    if series_result.description.present? && series.description != series_result.description
      updates[:description] = series_result.description
    end
    updates[:author_name] = author_name if author_name.present? && series.author_name != author_name
    updates[:artist_name] = artist_name if artist_name.present? && series.artist_name != artist_name
    updates[:cover_url] = series_result.cover_url if series_result.cover_url.present? && series.cover_url != series_result.cover_url

    # Store alternative titles and try to detect localized (JP/KR/CN) title
    alt_titles = Array(series_result.alt_titles).compact
    updates[:alt_titles] = alt_titles if alt_titles.any?
    localized = detect_localized_title(alt_titles)
    updates[:localized_title] = localized if localized.present? && series.localized_title != localized

    series.update!(updates)

    # Download and attach cover image if URL changed or no cover attached
    download_cover(series, series_result.cover_url)

    base_path = LibraryPathBuilder.new(series: series, source: @source).base_path
    if base_path.present? && series_source.library_base_path != base_path
      series_source.update!(library_base_path: base_path)
    end

    chapters.each do |chapter|
      next if chapter.number.blank?

      volume = nil
      if chapter.volume.present?
        volume = Volume.find_or_create_by!(series: series, volume_number: chapter.volume)
      end

      record = Chapter.find_or_initialize_by(
        series: series,
        source: @source,
        chapter_number: chapter.number,
        language: chapter.language,
        group: chapter.group
      )

      if record.new_record?
        record.title = chapter.title
        record.source_url = chapter.url
        record.volume = volume if volume
        record.save!
      else
        updates = {}
        updates[:title] = chapter.title if chapter.title.present? && record.title != chapter.title
        updates[:source_url] = chapter.url if chapter.url.present? && record.source_url != chapter.url
        updates[:volume] = volume if volume && record.volume_id != volume.id
        record.update!(updates) if updates.any?
      end
    end

    series
  end

  private

  def download_cover(series, cover_url)
    return if cover_url.blank?
    return if series.cover.attached? && series.cover_url == cover_url

    CoverDownloader.download(series, cover_url, source: @source)
  end

  # Detect a localized title (Japanese, Korean, or Chinese) from alt_titles
  # These typically contain CJK characters
  def detect_localized_title(alt_titles)
    # CJK Unicode ranges:
    # Japanese Hiragana: \u3040-\u309F
    # Japanese Katakana: \u30A0-\u30FF
    # CJK Unified Ideographs (Chinese/Japanese/Korean): \u4E00-\u9FFF
    # Korean Hangul: \uAC00-\uD7AF
    cjk_pattern = /[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]/

    alt_titles.find { |title| title.match?(cjk_pattern) }
  end
end
