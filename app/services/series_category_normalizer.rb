class SeriesCategoryNormalizer
  CANONICAL = %w[
    manga
    manhwa
    manhua
    webtoon
    comic
    shonen
    seinen
    shojo
    josei
    horror
    thriller
    action
  ].freeze

  STYLE_BY_CATEGORY = {
    "manhwa" => "webtoon",
    "manhua" => "webtoon",
    "webtoon" => "webtoon",
    "manga" => "left_to_right",
    "comic" => "left_to_right"
  }.freeze

  def normalize(tags:, series_type:)
    candidates = Array(tags).compact.map(&:to_s) + [ series_type ]
    normalized = candidates.map { |tag| tag.to_s.strip.downcase }
    normalized = normalized.select(&:present?).uniq
    normalized.select { |tag| CANONICAL.include?(tag) }
  end

  def normalize_with_style(tags:, series_type:)
    categories = normalize(tags: tags, series_type: series_type)
    style = style_for(categories, series_type)
    { categories: categories, reading_style: style }
  end

  private

  def style_for(categories, series_type)
    categories.each do |category|
      return STYLE_BY_CATEGORY[category] if STYLE_BY_CATEGORY.key?(category)
    end

    series_type.to_s.strip.downcase.in?(%w[manhwa manhua webtoon]) ? "webtoon" : "left_to_right"
  end
end
