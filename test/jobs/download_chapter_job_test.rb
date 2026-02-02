require "test_helper"
require "tmpdir"

class DownloadChapterJobTest < ActiveSupport::TestCase
  class FakeAdapter
    def pages(_chapter_url)
      [
        ResultTypes::Page.new(index: 1, url: "https://img.example.com/page-1.jpg", mime_type: "image/jpeg"),
        ResultTypes::Page.new(index: 2, url: "https://img.example.com/page-2.jpg", mime_type: "image/jpeg")
      ]
    end

    def config
      { "base_url" => "https://img.example.com" }
    end
  end

  class FakeHttpClient
    Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

    def initialize(bodies)
      @bodies = bodies
    end

    def get(url, headers: {}, params: {})
      Response.new(
        status: 200,
        body: @bodies.fetch(url),
        headers: { "content-type" => "image/jpeg" },
        url: url
      )
    end
  end

  def test_perform_creates_release_and_attaches_pages_scoped_to_source
    adapter = FakeAdapter.new
    http = FakeHttpClient.new(
      "https://img.example.com/page-1.jpg" => "page-1",
      "https://img.example.com/page-2.jpg" => "page-2"
    )
    job = DownloadChapterJob.new

    release = job.perform(
      "https://weebcentral.com/chapters/01CHAPTER",
      source_key: "weeb_central",
      series_title: "One Piece",
      source_series_id: "SERIES123",
      chapter_number: "1",
      chapter_title: "Chapter 1",
      adapter: adapter,
      http: http
    )

    release.reload
    assert_instance_of Release, release
    assert_equal "weeb_central", release.source.key
    assert_equal "One Piece", release.chapter.series.canonical_title
    assert_equal "1", release.chapter.chapter_number
    assert_equal "Chapter 1", release.chapter.title

    series_source = SeriesSource.find_by(source: release.source, series: release.chapter.series)
    assert_equal "SERIES123", series_source.source_series_id

    file_asset = release.file_asset
    pages = file_asset.pages.order(:position).to_a
    assert_equal [ 1, 2 ], pages.map(&:position)
    assert_equal [ "001.jpg", "002.jpg" ], pages.map { |page| page.image.filename.to_s }
    assert_equal [ "page-1", "page-2" ], pages.map { |page| page.image.download }
    assert_equal 2, file_asset.page_count
    assert_equal "complete", file_asset.download_status
    assert_equal 2, file_asset.pages_expected
    assert_equal 2, file_asset.pages_downloaded
    assert_nil file_asset.download_error
  end
end
