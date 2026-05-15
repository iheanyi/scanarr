require "test_helper"
require "zip"

class ChapterPackagerTest < ActiveSupport::TestCase
  def test_preloads_image_attachments_to_avoid_n_plus_1
    series = Series.create!(canonical_title: "Query Test")
    chapter = Chapter.create!(series: series, chapter_number: "1")
    release = Release.create!(chapter: chapter)
    file_asset = FileAsset.create!(release: release)

    5.times do |i|
      page = file_asset.pages.create!(position: i + 1)
      page.image.attach(io: StringIO.new("page-#{i}"), filename: "00#{i}.jpg", content_type: "image/jpeg")
    end

    packager = ChapterPackager.new(file_asset)

    # Measure queries during packaging (after construction)
    query_count = count_queries { packager.package! }

    # With 5 pages, an N+1 would fire 5+ attachment queries.
    # The fixed version uses includes(image_attachment: :blob) in a single query.
    # Budget: pages query(1) + attachment preload(~2) + blob reads(5 opens) + archive attach(~3)
    assert_operator query_count, :<, 20, "Expected fewer than 20 queries for 5 pages (got #{query_count}); possible N+1 on image attachments"
    assert_predicate file_asset.archive, :attached?
  end

  def test_packages_pages_into_cbz
    series = Series.create!(canonical_title: "One Piece")
    source = sources(:one)
    chapter = Chapter.create!(series: series, source: source, chapter_number: "1")
    release = Release.create!(chapter: chapter, source: source)
    path = LibraryPathBuilder.new(series: series, source: source).chapter_path(chapter)
    file_asset = FileAsset.create!(release: release, path: path)

    page1 = file_asset.pages.create!(position: 1)
    page1.image.attach(io: StringIO.new("page-1"), filename: "001.jpg", content_type: "image/jpeg")
    page2 = file_asset.pages.create!(position: 2)
    page2.image.attach(io: StringIO.new("page-2"), filename: "002.jpg", content_type: "image/jpeg")

    ChapterPackager.new(file_asset).package!

    assert_predicate file_asset.archive, :attached?
    assert_equal "#{path}/chapter.cbz", file_asset.archive.blob.key
    file_asset.archive.blob.open do |file|
      Zip::File.open(file.path) do |zip|
        assert_equal [ "001.jpg", "002.jpg" ], zip.entries.map(&:name)
        assert_equal "page-1", zip.read("001.jpg")
        assert_equal "page-2", zip.read("002.jpg")
      end
    end
  end
end
