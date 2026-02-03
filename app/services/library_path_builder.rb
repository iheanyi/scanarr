class LibraryPathBuilder
  def initialize(series:, source:)
    @series = series
    @source = source
  end

  def base_path
    title = slug(@series.canonical_title)
    author = slug(@series.display_author)
    return nil if title.blank?

    [ @source.key.to_s, [ title, author ].compact.join("-") ].join("/")
  end

  def chapter_path(chapter)
    base = base_path
    return nil if base.blank?

    volume_segment = normalize_numeric(chapter.volume&.volume_number) || "unknown"
    chapter_segment = normalize_numeric(chapter.chapter_number.presence || chapter.public_id) || "unknown"

    [ base, "volumes", volume_segment, "chapters", chapter_segment ].join("/")
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
end
