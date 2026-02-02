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

    series_source = SeriesSource.find_by(source: @source, source_series_id: series_result.id)
    series = series_source&.series

    series ||= Series.find_by(canonical_title: series_result.title)
    series ||= Series.create!(canonical_title: series_result.title)

    series_source = SeriesSource.find_or_create_by!(series: series, source: @source)
    if series_result.id.present? && series_source.source_series_id != series_result.id
      series_source.update!(source_series_id: series_result.id)
    end

    series.update!(
      raw_tags: Array(series_result.tags).compact,
      normalized_categories: normalized.fetch(:categories, []),
      reading_style: normalized.fetch(:reading_style, "left_to_right")
    )

    chapters.each do |chapter|
      next if chapter.number.blank?

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
        record.save!
      else
        updates = {}
        updates[:title] = chapter.title if chapter.title.present? && record.title != chapter.title
        updates[:source_url] = chapter.url if chapter.url.present? && record.source_url != chapter.url
        record.update!(updates) if updates.any?
      end
    end

    series
  end
end
