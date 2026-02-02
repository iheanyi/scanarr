require "test_helper"
require "zip"

class ChapterPackagerTest < ActiveSupport::TestCase
  def test_packages_pages_into_cbz
    series = Series.create!(canonical_title: "One Piece")
    chapter = Chapter.create!(series: series, chapter_number: "1")
    release = Release.create!(chapter: chapter)
    file_asset = FileAsset.create!(release: release)

    page1 = file_asset.pages.create!(position: 1)
    page1.image.attach(io: StringIO.new("page-1"), filename: "001.jpg", content_type: "image/jpeg")
    page2 = file_asset.pages.create!(position: 2)
    page2.image.attach(io: StringIO.new("page-2"), filename: "002.jpg", content_type: "image/jpeg")

    ChapterPackager.new(file_asset).package!

    assert file_asset.archive.attached?
    file_asset.archive.blob.open do |file|
      Zip::File.open(file.path) do |zip|
        assert_equal [ "001.jpg", "002.jpg" ], zip.entries.map(&:name)
        assert_equal "page-1", zip.read("001.jpg")
        assert_equal "page-2", zip.read("002.jpg")
      end
    end
  end
end
