require "test_helper"

class ChapterTest < ActiveSupport::TestCase
  def test_public_id_is_generated
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1")
    assert chapter.public_id.present?
    assert_equal 12, chapter.public_id.length
    assert_equal chapter.public_id, chapter.to_param
  end
end
