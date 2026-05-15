require "test_helper"

class SeriesImporterTest < ActiveSupport::TestCase
  class FakeAdapter
    def series(_url)
      ResultTypes::Series.new(
        id: "series-123",
        title: "One Piece",
        url: "https://weebcentral.com/series/OP",
        author: "Eiichiro Oda",
        artist: "Eiichiro Oda",
        tags: [ "Action", "Shonen" ],
        status: "ongoing",
        series_type: "manga"
      )
    end

    def chapters(_series_url)
      [
        ResultTypes::Chapter.new(id: "ch-1", title: "Chapter 1", number: "1", volume: "1", url: "https://weebcentral.com/chapters/01CHAPTER"),
        ResultTypes::Chapter.new(id: "ch-2", title: "Chapter 2", number: "2", volume: "1", url: "https://weebcentral.com/chapters/02CHAPTER")
      ]
    end
  end

  class MissingAuthorAdapter < FakeAdapter
    def series(_url)
      result = super
      ResultTypes::Series.new(result.to_h.merge(title: "One Piece Deluxe"))
    end
  end

  def test_import_creates_series_source_and_chapters
    source = sources(:one)
    importer = SeriesImporter.new(source: source, adapter: FakeAdapter.new)

    series = importer.import!("https://weebcentral.com/series/OP")

    assert_equal "One Piece", series.canonical_title
    assert_equal "Eiichiro Oda", series.author_name
    assert_equal "Eiichiro Oda", series.artist_name
    assert_equal [ "Action", "Shonen" ], series.raw_tags
    assert_includes series.normalized_categories, "manga"
    assert_equal "left_to_right", series.reading_style
    series_source = SeriesSource.find_by!(series: series, source: source, source_series_id: "series-123")

    assert_equal "library/weeb_central/one-piece--#{series.public_id}", series_source.library_base_path
    assert_equal 2, series.chapters.where(source: source).count
    assert_equal "https://weebcentral.com/chapters/01CHAPTER", series.chapters.find_by(chapter_number: "1").source_url
    assert_equal "1", series.chapters.find_by(chapter_number: "1").volume&.volume_number
  end

  def test_import_dedupes_by_title_with_missing_author
    source = sources(:one)
    existing = Series.create!(canonical_title: "One Piece Deluxe")
    importer = SeriesImporter.new(source: source, adapter: MissingAuthorAdapter.new)

    assert_difference -> { Series.count }, 0 do
      series = importer.import!("https://weebcentral.com/series/OP")

      assert_equal existing.id, series.id
    end
  end
end
