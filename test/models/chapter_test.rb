require "test_helper"

class ChapterTest < ActiveSupport::TestCase
  def test_public_id_is_generated
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1")

    assert_predicate chapter.public_id, :present?
    assert_equal 12, chapter.public_id.length
    assert_equal chapter.public_id, chapter.to_param
  end

  def test_chapter_number_normalizes_expanded_float_precision
    series = Series.create!(canonical_title: "Oshi No Ko")
    chapter = Chapter.create!(
      series: series,
      chapter_number: "125.80000305175781",
      title: "Chapter 125.8"
    )

    assert_equal "125.8", chapter.chapter_number
    assert_equal BigDecimal("125.8"), chapter.chapter_number_value
  end

  def test_chapter_number_normalization_uses_chapter_label_before_volume_number
    series = Series.create!(canonical_title: "Berserk")
    chapter = Chapter.create!(
      series: series,
      chapter_number: "0.10000000149011612",
      title: "Vol.4 Ch.0.10 - The Golden Age"
    )

    assert_equal "0.10", chapter.chapter_number
    assert_equal BigDecimal("0.10"), chapter.chapter_number_value
  end

  def test_meaningful_title_returns_false_for_blank_title
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1", title: nil)

    assert_not chapter.meaningful_title?

    chapter.update!(title: "")

    assert_not chapter.meaningful_title?
  end

  def test_meaningful_title_returns_false_for_chapter_number_title
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "2", title: "Chapter 2")

    assert_not chapter.meaningful_title?

    chapter.update!(title: "chapter 2")

    assert_not chapter.meaningful_title?

    chapter.update!(title: "Chapter  2")

    assert_not chapter.meaningful_title?
  end

  def test_meaningful_title_returns_true_for_real_title
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1", title: "Romance Dawn")

    assert_predicate chapter, :meaningful_title?

    chapter.update!(title: "Chapter 1: Romance Dawn")

    assert_predicate chapter, :meaningful_title?

    chapter.update!(title: "The Beginning")

    assert_predicate chapter, :meaningful_title?
  end

  def test_display_title_returns_nil_for_non_meaningful
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "2", title: "Chapter 2")

    assert_nil chapter.display_title
  end

  def test_display_title_returns_title_for_meaningful
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1", title: "Romance Dawn")

    assert_equal "Romance Dawn", chapter.display_title
  end
end
