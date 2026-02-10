require "test_helper"

class SeriesCategoryNormalizerTest < ActiveSupport::TestCase
  def test_normalizes_known_tags
    normalizer = SeriesCategoryNormalizer.new
    raw = [ "Shonen", "Horror", "Webtoon" ]

    categories = normalizer.normalize(tags: raw, series_type: "manga")

    assert_includes categories, "shonen"
    assert_includes categories, "horror"
    assert_includes categories, "webtoon"
    assert_includes categories, "manga"
  end

  def test_defaults_reading_style_for_manhwa
    normalizer = SeriesCategoryNormalizer.new
    result = normalizer.normalize_with_style(tags: [ "Manhwa" ], series_type: "manhwa")

    assert_equal "webtoon", result.fetch(:reading_style)
  end
end
