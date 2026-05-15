class LibraryPathBuilder
  def initialize(series:, source:)
    @series = series
    @source = source
  end

  def base_path
    title = slug(@series.canonical_title)
    return nil if title.blank?

    source = slug(@source&.key || @source&.slug || "unknown_source")
    series_id = slug(@series.public_id.presence || @series.id || "unsaved")

    [ "library", source, "#{title}--#{series_id}" ].join("/")
  end

  def chapter_path(chapter)
    base = base_path
    return nil if base.blank?

    volume_segment = normalize_numeric(chapter.volume&.volume_number) || "unknown"
    chapter_number = normalize_numeric(chapter.chapter_number.presence || chapter.public_id) || "unknown"
    chapter_id = slug(chapter.public_id.presence || chapter.id || "unsaved")
    chapter_segment = "#{chapter_number}--#{chapter_id}"

    [ base, "volumes", volume_segment, "chapters", chapter_segment ].join("/")
  end

  def page_path(chapter, position:, extension:)
    base = chapter_path(chapter)
    return nil if base.blank?

    [ base, "pages", "#{format('%03d', position)}.#{normalize_extension(extension)}" ].join("/")
  end

  def cover_path(extension:)
    base = base_path
    return nil if base.blank?

    [ base, "covers", "cover.#{normalize_extension(extension)}" ].join("/")
  end

  def archive_path(chapter, extension: "cbz")
    base = chapter_path(chapter)
    return nil if base.blank?

    [ base, "chapter.#{normalize_extension(extension)}" ].join("/")
  end

  private

  def slug(value)
    value.to_s.parameterize.presence
  end

  def normalize_numeric(value)
    return nil if value.blank?

    raw = value.to_s.strip
    return raw if raw.match?(/\A[\d.]+\z/)

    raw.parameterize
  end

  def normalize_extension(extension)
    extension.to_s.delete_prefix(".").parameterize.presence || "bin"
  end
end
