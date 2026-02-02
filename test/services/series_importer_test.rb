require "test_helper"

class SeriesImporterTest < ActiveSupport::TestCase
  class FakeAdapter
    def series(_url)
      ResultTypes::Series.new(
        id: "series-123",
        title: "One Piece",
        url: "https://weebcentral.com/series/OP",
        tags: [ "Action", "Shonen" ],
        status: "ongoing",
        series_type: "manga"
      )
    end

    def chapters(_series_url)
      [
        ResultTypes::Chapter.new(id: "ch-1", title: "Chapter 1", number: "1", url: "https://weebcentral.com/chapters/01CHAPTER"),
        ResultTypes::Chapter.new(id: "ch-2", title: "Chapter 2", number: "2", url: "https://weebcentral.com/chapters/02CHAPTER")
      ]
    end
  end

  def test_import_creates_series_source_and_chapters
    source = sources(:one)
    importer = SeriesImporter.new(source: source, adapter: FakeAdapter.new)

    series = importer.import!("https://weebcentral.com/series/OP")

    assert_equal "One Piece", series.canonical_title
    assert_equal [ "Action", "Shonen" ], series.raw_tags
    assert_includes series.normalized_categories, "manga"
    assert_equal "left_to_right", series.reading_style
    assert SeriesSource.find_by!(series: series, source: source, source_series_id: "series-123")
    assert_equal 2, series.chapters.where(source: source).count
    assert_equal "https://weebcentral.com/chapters/01CHAPTER", series.chapters.find_by(chapter_number: "1").source_url
  end
end
