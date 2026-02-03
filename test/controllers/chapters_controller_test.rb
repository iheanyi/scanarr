require "test_helper"

class ChaptersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
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

  def test_update_progress_requires_authentication
    patch "/sources/weeb-central/one-piece/chapters/1/progress",
          params: { page_index: 1, page_count: 5 },
          headers: { "ACCEPT" => "application/json" }

    assert_response :unauthorized
    assert_includes @response.body, "sign in"
  end

  def test_update_progress_creates_progress
    sign_in users(:one)

    assert_difference -> { ChapterProgress.count }, 1 do
      patch "/sources/weeb-central/one-piece/chapters/1/progress",
            params: { page_index: 2, page_count: 5 },
            headers: { "ACCEPT" => "application/json" }
    end

    progress = ChapterProgress.order(created_at: :desc).first
    assert_equal 2, progress.page_index
    assert_equal 5, progress.page_count
    assert_equal "in_progress", progress.status
    assert progress.progressed_at.present?
    assert_response :success
  end

  def test_show_renders_progress_bar
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      assert_includes @response.body, "data-reader-target=\"progressText\""
      assert_includes @response.body, "data-reader-target=\"progressBar\""
    end
  end

  def test_show_uses_saved_progress_for_initial_page
    user = users(:one)
    ChapterProgress.create!(
      user: user,
      chapter: chapters(:one),
      page_index: 2,
      page_count: 2,
      status: "completed",
      progressed_at: Time.current
    )

    sign_in user
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      assert_includes @response.body, "Page 2 / 2"
    end
  end

  def test_show_renders_lightbox_toggle
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      assert_includes @response.body, "data-action=\"click->reader#toggleLightbox\""
    end
  end

  def test_show_renders_lightbox_overlay
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      assert_includes @response.body, "data-reader-target=\"lightbox\""
      assert_includes @response.body, "data-reader-target=\"lightboxImage\""
    end
  end

  def test_show_renders_lightbox_inside_reader_controller
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      main = @response.body[/<main[^>]*data-controller="reader".*?<\/main>/m]
      assert main, "Expected reader controller markup to be present"
      assert_includes main, "data-reader-target=\"lightbox\""
    end
  end

  def test_show_caps_reader_image_size
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1"
      assert_response :success
      assert_includes @response.body, "max-w-2xl"
      assert_includes @response.body, "max-h-[75vh]"
    end
  end

  def test_show_prefers_page_param_for_initial_page
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/one-piece/chapters/1", params: { page: 2 }
      assert_response :success
      assert_includes @response.body, "Page 2 / 2"
    end
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

  def test_remove_download_deletes_file_asset
    chapter = chapters(:one)
    release = releases(:one)
    file_asset = file_assets(:one)

    assert file_asset.persisted?
    assert_equal "complete", file_asset.download_status

    delete "/sources/weeb-central/one-piece/chapters/#{chapter.chapter_number}/download"

    assert_redirected_to "/sources/weeb-central/one-piece"
    assert_not FileAsset.exists?(file_asset.id)
  end

  def test_remove_download_shows_flash_message
    chapter = chapters(:one)

    delete "/sources/weeb-central/one-piece/chapters/#{chapter.chapter_number}/download"

    assert_redirected_to "/sources/weeb-central/one-piece"
    follow_redirect!
    assert_includes @response.body, "Download removed"
  end

  def test_cancel_download_cancels_queued_download
    chapter = chapters(:two)
    release = releases(:two)
    file_asset = file_assets(:two)
    file_asset.update!(download_status: "queued")

    post "/sources/weeb-central/one-piece/chapters/#{chapter.chapter_number}/cancel_download"

    assert_redirected_to "/sources/weeb-central/one-piece"
    assert_not FileAsset.exists?(file_asset.id)
  end

  def test_cancel_download_marks_downloading_as_failed
    chapter = chapters(:two)
    release = releases(:two)
    file_asset = file_assets(:two)
    file_asset.update!(download_status: "downloading")

    post "/sources/weeb-central/one-piece/chapters/#{chapter.chapter_number}/cancel_download"

    assert_redirected_to "/sources/weeb-central/one-piece"
    file_asset.reload
    assert_equal "failed", file_asset.download_status
    assert_equal "Cancelled by user", file_asset.download_error
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
