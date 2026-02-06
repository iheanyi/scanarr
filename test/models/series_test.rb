require "test_helper"

class SeriesTest < ActiveSupport::TestCase
  def test_generates_slug_from_title
    series = Series.create!(canonical_title: "One Piece Omega")

    assert_equal "one-piece-omega", series.slug
  end

  def test_slug_is_unique
    first = Series.create!(canonical_title: "Slug Test")
    second = Series.create!(canonical_title: "Slug Test")

    assert first.slug.start_with?("slug-test")
    assert second.slug.start_with?("slug-test")
    assert_not_equal first.slug, second.slug
  end

  def test_public_id_is_generated
    series = Series.create!(canonical_title: "One Piece")

    assert_predicate series.public_id, :present?
    assert_equal 12, series.public_id.length
  end

  def test_persists_reading_style_and_categories
    series = Series.create!(
      canonical_title: "One Piece",
      reading_style: "left_to_right",
      raw_tags: [ "Action", "Shonen" ],
      normalized_categories: [ "manga", "shonen" ]
    )

    assert_equal "left_to_right", series.reading_style
    assert_equal [ "Action", "Shonen" ], series.raw_tags
    assert_equal [ "manga", "shonen" ], series.normalized_categories
  end

  def test_display_author_prefers_author_then_artist
    series = Series.create!(
      canonical_title: "One Piece",
      author_name: "Eiichiro Oda",
      artist_name: "Eiichiro Oda"
    )

    assert_equal "Eiichiro Oda", series.display_author

    series.update!(author_name: nil, artist_name: "Another Artist")

    assert_equal "Another Artist", series.display_author

    series.update!(artist_name: nil)

    assert_nil series.display_author
  end
end
