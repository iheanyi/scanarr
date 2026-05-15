require "test_helper"

class LibraryPathBuilderTest < ActiveSupport::TestCase
  def test_base_and_chapter_paths
    series = Series.create!(canonical_title: "One Piece", author_name: "Eiichiro Oda")
    source = sources(:one)
    builder = LibraryPathBuilder.new(series: series, source: source)

    assert_equal "library/weeb_central/one-piece--#{series.public_id}", builder.base_path

    chapter = Chapter.create!(series: series, source: source, chapter_number: "1.5")

    expected_chapter_path = "library/weeb_central/one-piece--#{series.public_id}/volumes/unknown/chapters/1.5--#{chapter.public_id}"

    assert_equal expected_chapter_path, builder.chapter_path(chapter)
    assert_equal "#{expected_chapter_path}/pages/001.jpg", builder.page_path(chapter, position: 1, extension: "jpg")

    volume = Volume.new(series: series, volume_number: "2")
    chapter.volume = volume

    volume_chapter_path = "library/weeb_central/one-piece--#{series.public_id}/volumes/2/chapters/1.5--#{chapter.public_id}"

    assert_equal volume_chapter_path, builder.chapter_path(chapter)
    assert_equal "#{volume_chapter_path}/pages/001.jpg", builder.page_path(chapter, position: 1, extension: "jpg")
    assert_equal "library/weeb_central/one-piece--#{series.public_id}/covers/cover.webp", builder.cover_path(extension: "webp")
    assert_equal "#{volume_chapter_path}/chapter.cbz", builder.archive_path(chapter)
  end
end
