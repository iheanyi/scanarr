require "test_helper"
require "tmpdir"

class ChapterDownloaderTest < ActiveSupport::TestCase
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

  def test_download_writes_files_to_disk
    adapter = FakeAdapter.new
    http = FakeHttpClient.new(
      "https://img.example.com/page-1.jpg" => "page-1",
      "https://img.example.com/page-2.jpg" => "page-2"
    )
    downloader = ChapterDownloader.new(adapter: adapter, http: http)

    Dir.mktmpdir do |dir|
      files = downloader.download("https://weebcentral.com/chapters/01CHAPTER", output_dir: dir)

      assert_equal 2, files.size
      assert_equal [ "001.jpg", "002.jpg" ], files.map { |f| File.basename(f) }
      assert_equal "page-1", File.binread(files[0])
      assert_equal "page-2", File.binread(files[1])
    end
  end
end
