require "test_helper"

class LibraryPathBuilderTest < ActiveSupport::TestCase
  def test_base_and_chapter_paths
    series = Series.create!(canonical_title: "One Piece", author_name: "Eiichiro Oda")
    source = sources(:one)
    builder = LibraryPathBuilder.new(series: series, source: source)

    assert_equal "weeb_central/one-piece-eiichiro-oda", builder.base_path

    chapter = Chapter.new(series: series, chapter_number: "1.5")
    assert_equal "weeb_central/one-piece-eiichiro-oda/volumes/unknown/chapters/1.5", builder.chapter_path(chapter)

    volume = Volume.new(series: series, volume_number: "2")
    chapter.volume = volume
    assert_equal "weeb_central/one-piece-eiichiro-oda/volumes/2/chapters/1.5", builder.chapter_path(chapter)
  end
end
