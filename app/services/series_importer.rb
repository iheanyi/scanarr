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
      cover_url: series_result.cover_url
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
    updates[:author_name] = author_name if author_name.present? && series.author_name != author_name
    updates[:artist_name] = artist_name if artist_name.present? && series.artist_name != artist_name
    updates[:cover_url] = series_result.cover_url if series_result.cover_url.present? && series.cover_url != series_result.cover_url
    series.update!(updates)

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
end
