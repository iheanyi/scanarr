require "test_helper"
require "base64"
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
        headers: { "content-type" => "image/png" },
        url: url
      )
    end
  end

  class FakeStep
    attr_reader :cursor

    def initialize(cursor = nil)
      @cursor = cursor
    end

    def advance!(from:)
      @cursor = from
    end
  end

  def test_perform_creates_release_and_attaches_pages_scoped_to_source
    tiny_png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2Z8x0AAAAASUVORK5CYII=")
    adapter = FakeAdapter.new
    http = FakeHttpClient.new(
      "https://img.example.com/page-1.jpg" => tiny_png,
      "https://img.example.com/page-2.jpg" => tiny_png
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
    assert_equal "weeb_central/one-piece", series_source.library_base_path

    file_asset = release.file_asset

    assert_equal "weeb_central/one-piece/volumes/unknown/chapters/1", file_asset.path
    pages = file_asset.pages.order(:position).to_a

    assert_equal [ 1, 2 ], pages.map(&:position)
    assert_equal [ "001.png", "002.png" ], pages.map { |page| page.image.filename.to_s }
    assert_equal [ "image/png", "image/png" ], pages.map { |page| page.image.content_type }
    assert_equal 2, file_asset.page_count
    assert_equal "complete", file_asset.download_status
    assert_equal 2, file_asset.pages_expected
    assert_equal 2, file_asset.pages_downloaded
    assert_nil file_asset.download_error
  end

  def test_fetch_pages_rehydrates_entities_when_runtime_state_is_missing
    release = Release.create!(
      chapter: chapters(:one),
      source: sources(:one),
      format: "pages",
      source_url: "https://weebcentral.com/chapters/resume-#{SecureRandom.hex(4)}"
    )

    job = build_resume_job(release: release, adapter: FakeAdapter.new)

    assert_nil job.instance_variable_get(:@file_asset)

    job.send(:fetch_pages)

    release.reload

    assert_not_nil release.file_asset
    assert_equal "downloading", release.file_asset.download_status
    assert_equal 2, release.file_asset.pages_expected
  end

  def test_download_and_finalize_rehydrate_entities_when_runtime_state_is_missing
    release = Release.create!(
      chapter: chapters(:one),
      source: sources(:one),
      format: "pages",
      source_url: "https://weebcentral.com/chapters/resume-full-#{SecureRandom.hex(4)}"
    )
    http = FakeHttpClient.new(
      "https://img.example.com/page-1.jpg" => tiny_png,
      "https://img.example.com/page-2.jpg" => tiny_png
    )
    job = build_resume_job(release: release, adapter: FakeAdapter.new, http: http)
    step = FakeStep.new

    job.send(:fetch_pages)

    clear_runtime_entities!(job)
    job.send(:download_pages_with_cursor, step)

    clear_runtime_entities!(job)
    job.send(:finalize)

    release.reload
    file_asset = release.file_asset

    assert_equal 2, file_asset.pages.count
    assert_equal 2, file_asset.pages_downloaded
    assert_equal 2, file_asset.page_count
    assert_equal "complete", file_asset.download_status
    assert_equal 2, step.cursor
  end

  def test_ensure_runtime_entities_raises_when_rehydration_is_incomplete
    job = DownloadChapterJob.new
    job.define_singleton_method(:setup_entities) { }

    error = assert_raises(RuntimeError) do
      job.send(:ensure_runtime_entities!)
    end

    assert_match("Runtime rehydration incomplete", error.message)
  end

  private

  def tiny_png
    @tiny_png ||= Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2Z8x0AAAAASUVORK5CYII=")
  end

  def build_resume_job(release:, adapter:, http: nil)
    job = DownloadChapterJob.new
    job.instance_variable_set(:@chapter_url, release.source_url)
    job.instance_variable_set(:@source_key, release.source.key)
    job.instance_variable_set(:@series_title, release.chapter.series.canonical_title)
    job.instance_variable_set(:@source_series_id, nil)
    job.instance_variable_set(:@chapter_number, release.chapter.chapter_number)
    job.instance_variable_set(:@chapter_title, release.chapter.title)
    job.instance_variable_set(:@language, release.chapter.language)
    job.instance_variable_set(:@group, release.chapter.group)
    job.instance_variable_set(:@release_id, release.id)
    job.instance_variable_set(:@adapter, adapter)
    job.instance_variable_set(:@http, http) if http
    job
  end

  def clear_runtime_entities!(job)
    %i[@source @series @chapter @release @file_asset @pages].each do |ivar|
      job.instance_variable_set(ivar, nil)
    end
  end
end
