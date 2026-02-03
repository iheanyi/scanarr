require "test_helper"

class ChaptersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  class FakeAdapter
    def pages(_url)
      []
    end
  end

  setup do
    pages(:one).image.attach(io: StringIO.new("page-1"), filename: "001.jpg", content_type: "image/jpeg")
    pages(:two).image.attach(io: StringIO.new("page-2"), filename: "002.jpg", content_type: "image/jpeg")
  end

  def test_show_includes_next_chapter_link
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      assert_includes @response.body, "/sources/weeb-central/one-piece/chapters/2"
    end
  end

  def test_show_includes_previous_chapter_link
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/2"
      assert_response :success
      assert_includes @response.body, "/sources/weeb-central/one-piece/chapters/1"
    end
  end

  def test_navigation_orders_chapters_numerically
    series = series(:one)
    source = sources(:one)
    Chapter.create!(series: series, source: source, chapter_number: "10", title: "Chapter 10")
    Chapter.create!(series: series, source: source, chapter_number: "10.5", title: "Chapter 10.5")
    Chapter.create!(series: series, source: source, chapter_number: "Extra", title: "Chapter 10 Extra")

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/10"
      assert_response :success
      assert_includes @response.body, "/sources/weeb-central/one-piece/chapters/Extra"
    end
  end

  def test_show_handles_missing_release
    Chapter.where(chapter_number: "1").update_all(source_url: "https://weebcentral.com/chapters/01CHAPTER")
    release = Release.find_by(chapter_id: Chapter.find_by(chapter_number: "1").id)
    release&.file_asset&.destroy
    release&.destroy

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      assert_includes @response.body, "Streaming from source"
    end
  end

  def test_show_handles_missing_file_asset
    release = Release.find_by(chapter_id: Chapter.find_by(chapter_number: "1").id)
    release&.file_asset&.destroy

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      assert_includes @response.body, "Streaming from source"
    end
  end

  def test_download_enqueues_job
    clear_enqueued_jobs
    assert_difference -> { Release.count }, 1 do
      assert_difference -> { FileAsset.count }, 1 do
        assert_enqueued_jobs 1 do
          post "/sources/weeb-central/one-piece/chapters/1/download"
        end
      end
    end

    release = Release.order(created_at: :desc).first
    assert_equal "queued", release.file_asset.download_status
    job = enqueued_jobs.last
    assert_equal DownloadChapterJob, job[:job]
  end

  def test_show_disables_download_when_queued
    file_assets(:two).update!(download_status: "queued")

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/2"
      assert_response :success
      assert_includes @response.body, "Download queued"
      assert_match(/disabled=\"disabled\"/, @response.body)
    end
  end

  private

  def with_adapter(adapter)
    original = ChaptersController.instance_method(:adapter_for) rescue nil
    ChaptersController.define_method(:adapter_for) { |_source = nil| adapter }
    yield
  ensure
    if original
      ChaptersController.define_method(:adapter_for, original)
    else
      ChaptersController.remove_method(:adapter_for)
    end
  end
end
