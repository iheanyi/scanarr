require "test_helper"

class ReleaseTest < ActiveSupport::TestCase
  def test_public_id_is_generated
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1")
    release = Release.create!(chapter: chapter)

    assert_predicate release.public_id, :present?
    assert_equal 12, release.public_id.length
    assert_equal release.public_id, release.to_param
  end
end
