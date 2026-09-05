require "test_helper"

class ChaptersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class FakeAdapter
    attr_reader :http

    def initialize(pages: [], http: FakeHttp.new)
      @pages = pages
      @http = http
    end

    def pages(_url)
      @pages
    end
  end

  class FakeHttp
    def initialize(status: 200, body: "image-bytes", headers: { "content-type" => "image/jpeg" })
      @status = status
      @body = body
      @headers = headers
    end

    def get(_url)
      Struct.new(:status, :body, :headers).new(@status, @body, @headers)
    end
  end

  setup do
    pages(:one).image.attach(io: StringIO.new("page-1"), filename: "001.jpg", content_type: "image/jpeg")
    pages(:two).image.attach(io: StringIO.new("page-2"), filename: "002.jpg", content_type: "image/jpeg")
    @series = series(:one)
  end

  def series_url
    "#{@series.public_id}-#{@series.slug}"
  end

  def test_show_includes_next_chapter_link
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, chapter_public_path(public_id: chapters(:two).public_id)
    end
  end

  def test_show_includes_previous_chapter_link
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/2"

      assert_response :success
      assert_includes @response.body, chapter_public_path(public_id: chapters(:one).public_id)
    end
  end

  def test_show_marks_reader_pages_for_image_loading_skeleton
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_select "section.scanarr-reader-viewport"
      assert_select "article.scanarr-reader-page-frame[data-reader-image-state='loading']" do
        assert_select "img.scanarr-reader-image[data-action*='load->reader#markImageLoaded']"
        assert_select "img.scanarr-reader-image[data-action*='error->reader#markImageLoaded']"
      end
    end
  end

  def test_show_supports_decimal_chapter_identifiers
    source = sources(:one)
    Chapter.create!(
      series: @series,
      source: source,
      chapter_number: "262.2",
      chapter_number_value: 262.2,
      title: "Chapter 262.2",
      source_url: "https://weebcentral.com/chapters/262-2"
    )

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/262.2"

      assert_response :success
      assert_includes @response.body, "Chapter 262.2"
    end
  end

  def test_navigation_orders_chapters_numerically
    source = sources(:one)
    Chapter.create!(series: @series, source: source, chapter_number: "10", title: "Chapter 10")
    Chapter.create!(series: @series, source: source, chapter_number: "10.5", title: "Chapter 10.5")
    Chapter.create!(series: @series, source: source, chapter_number: "Extra", title: "Chapter 10 Extra")

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/10"

      assert_response :success
      assert_includes @response.body, chapter_public_path(public_id: @series.chapters.find_by!(chapter_number: "10.5").public_id)
    end
  end

  def test_show_handles_missing_release
    Chapter.where(chapter_number: "1").update_all(source_url: "https://weebcentral.com/chapters/01CHAPTER")
    release = Release.find_by(chapter_id: Chapter.find_by(chapter_number: "1").id)
    release&.file_asset&.destroy
    release&.destroy

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, "Streaming from source"
    end
  end

  def test_show_handles_missing_file_asset
    release = Release.find_by(chapter_id: Chapter.find_by(chapter_number: "1").id)
    release&.file_asset&.destroy

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, "Streaming from source"
    end
  end

  def test_show_renders_download_progress_panel
    file_assets(:two).update!(
      download_status: "downloading",
      pages_downloaded: 4,
      pages_expected: 10
    )

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/2"

      assert_response :success
      assert_includes @response.body, "Downloading pages"
      assert_includes @response.body, "4/10 pages"
      assert_select "div[role='progressbar'][aria-valuenow='4'][aria-valuemax='10']"
    end
  end

  def test_download_enqueues_job
    clear_enqueued_jobs
    assert_no_difference -> { Release.count } do
      assert_no_difference -> { FileAsset.count } do
        assert_enqueued_jobs 1 do
          post "/sources/weeb-central/#{series_url}/chapters/1/download"
        end
      end
    end

    release = chapters(:one).releases.where(source: sources(:one)).order(created_at: :desc).first

    assert_equal "queued", release.file_asset.reload.download_status
    job = enqueued_jobs.last

    assert_equal DownloadChapterJob, job[:job]
  end

  def test_download_turbo_stream_includes_toast
    clear_enqueued_jobs

    post "/sources/weeb-central/#{series_url}/chapters/1/download",
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_includes @response.body, "toast-container"
    assert_includes @response.body, "Queued download for Chapter 1"
  end

  def test_download_requeues_failed_orphaned_file_asset
    clear_enqueued_jobs
    release = releases(:one)
    file_asset = file_assets(:one)
    file_asset.update!(
      download_status: "failed",
      download_error: "Orphaned: blob files missing from storage (detected by cleanup job)",
      pages_downloaded: 2,
      path: "library/old-layout"
    )

    assert_no_difference -> { FileAsset.count } do
      assert_enqueued_jobs 1 do
        post "/sources/weeb-central/#{series_url}/chapters/1/download"
      end
    end

    file_asset.reload
    expected_path = "library/weeb-central/one-piece--#{@series.public_id}/chapters/1--#{chapters(:one).public_id}"

    assert_redirected_to "/sources/weeb-central/#{series_url}/chapters/1"
    assert_equal release.file_asset, file_asset
    assert_equal "queued", file_asset.download_status
    assert_nil file_asset.download_error
    assert_equal 0, file_asset.pages_downloaded
    assert_equal expected_path, file_asset.path
  end

  def test_show_labels_failed_download_as_redownload
    file_assets(:one).update!(
      download_status: "failed",
      download_error: "Orphaned: blob files missing from storage (detected by cleanup job)"
    )

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"
    end

    assert_response :success
    assert_includes @response.body, "Download again to server"
  end

  def test_update_progress_creates_progress
    assert_difference -> { ChapterProgress.count }, 1 do
      patch "/sources/weeb-central/#{series_url}/chapters/1/progress",
            params: { page_index: 2, page_count: 5 },
            headers: { "ACCEPT" => "application/json" }
    end

    progress = ChapterProgress.order(created_at: :desc).first

    assert_equal 2, progress.page_index
    assert_equal 5, progress.page_count
    assert_equal "in_progress", progress.status
    assert_predicate progress.progressed_at, :present?
    assert_response :success
  end

  def test_pin_for_offline_creates_manifest_entry
    enable_local_download_mode

    assert_difference -> { UserOfflineManifestEntry.count }, 1 do
      post "/sources/weeb-central/#{series_url}/chapters/1/pin_for_offline", headers: { "ACCEPT" => "application/json" }
    end

    assert_response :success
    entry = UserOfflineManifestEntry.order(created_at: :desc).first

    assert_equal chapters(:one), entry.chapter
    assert_equal users(:admin), entry.user
    assert_equal "pinned", entry.status
  end

  def test_unpin_for_offline_removes_manifest_entry
    enable_local_download_mode
    UserOfflineManifestEntry.create!(user: users(:admin), chapter: chapters(:one), status: "pinned")

    assert_difference -> { UserOfflineManifestEntry.count }, -1 do
      delete "/sources/weeb-central/#{series_url}/chapters/1/pin_for_offline", headers: { "ACCEPT" => "application/json" }
    end

    assert_response :success
  end

  def test_offline_pages_returns_signed_proxy_urls_and_proxy_streams_image
    enable_local_download_mode
    file_assets(:one).update!(download_status: "failed")
    adapter = FakeAdapter.new(
      pages: [ Scrapers::ResultTypes::Page.new(index: 1, url: "https://example.test/chapter/1/page-1.jpg") ],
      http: FakeHttp.new(body: "proxied-image-data")
    )

    with_adapter(adapter) do
      get "/sources/weeb-central/#{series_url}/chapters/1/offline_pages", headers: { "ACCEPT" => "application/json" }

      assert_response :success

      payload = JSON.parse(@response.body)

      assert_equal 1, payload["page_count"]
      assert_equal "remote", payload["pages"][0]["source"]
      page_url = payload["pages"][0]["url"]

      assert_match %r{\A/sources/weeb-central/offline_image\?}, page_url
      query = Rack::Utils.parse_query(URI.parse(page_url).query)

      assert_predicate query["token"], :present?
      assert_predicate query["cache_key"], :present?

      get page_url, headers: { "ACCEPT" => "image/jpeg" }

      assert_response :success
      assert_equal "image/jpeg", @response.media_type
      assert_equal "proxied-image-data", @response.body
    end
  end

  def test_offline_image_proxy_is_available_when_local_downloads_are_disabled
    users(:admin).update!(local_downloads_enabled: "false")
    adapter = FakeAdapter.new(http: FakeHttp.new(body: "proxied-image-data"))
    token = Rails.application.message_verifier(:chapter_offline_image).generate(
      {
        source_slug: "weeb-central",
        page_url: "https://example.test/chapter/1/page-1.jpg"
      },
      purpose: "chapter_offline_image",
      expires_in: 6.hours
    )

    with_adapter(adapter) do
      get "/sources/weeb-central/offline_image", params: { token: token, cache_key: "ignored" }, headers: { "ACCEPT" => "image/jpeg" }

      assert_response :success
      assert_equal "image/jpeg", @response.media_type
      assert_equal "proxied-image-data", @response.body
    end
  end

  def test_offline_endpoints_require_local_downloads_toggle
    users(:admin).update!(local_downloads_enabled: "false")

    post "/sources/weeb-central/#{series_url}/chapters/1/pin_for_offline", headers: { "ACCEPT" => "application/json" }

    assert_response :forbidden
    payload = JSON.parse(@response.body)

    assert_includes payload["error"], "disabled"
  end

  def test_show_renders_progress_bar
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, "data-reader-target=\"progressText\""
      assert_includes @response.body, "data-reader-target=\"progressBar\""
    end
  end

  def test_show_uses_saved_progress_for_initial_page
    admin = users(:admin)
    ChapterProgress.create!(
      user: admin,
      chapter: chapters(:one),
      page_index: 2,
      page_count: 2,
      status: "completed",
      progressed_at: Time.current
    )

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, "Page 2 / 2"
    end
  end

  def test_show_opens_lightbox_from_page_click
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, "click->reader#openLightboxForPage"
    end
  end

  def test_show_renders_lightbox_overlay
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, "data-reader-target=\"lightbox\""
      assert_includes @response.body, "data-reader-target=\"lightboxImage lightboxPanel\""
    end
  end

  def test_show_uses_swipe_actions_and_hides_lightbox_arrows_on_mobile
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, "reader#lightboxPointerDown"
      assert_includes @response.body, "reader#lightboxPointerMove"
      assert_includes @response.body, "reader#lightboxPointerUp"
      assert_includes @response.body, "lightbox-nav-arrow absolute left-6"
      assert_includes @response.body, "lightbox-nav-arrow absolute right-6"
    end
  end

  def test_show_renders_lightbox_inside_reader_controller
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      main = @response.body[/<main[^>]*data-controller="reader".*?<\/main>/m]

      assert main, "Expected reader controller markup to be present"
      assert_includes main, "data-reader-target=\"lightbox\""
    end
  end

  def test_show_caps_reader_image_size
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1"

      assert_response :success
      assert_includes @response.body, "max-w-5xl"
      assert_includes @response.body, "max-h-[75vh]"
    end
  end

  def test_show_prefers_page_param_for_initial_page
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/1", params: { page: 2 }

      assert_response :success
      assert_includes @response.body, "Page 2 / 2"
    end
  end

  def test_show_disables_download_when_queued
    file_assets(:two).update!(download_status: "queued")

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/#{series_url}/chapters/2"

      assert_response :success
      assert_includes @response.body, "Download queued"
      assert_match(/disabled=\"disabled\"/, @response.body)
    end
  end

  def test_remove_download_deletes_file_asset
    chapter = chapters(:one)
    release = releases(:one)
    file_asset = file_assets(:one)

    assert_predicate file_asset, :persisted?
    assert_equal "complete", file_asset.download_status

    delete "/sources/weeb-central/#{series_url}/chapters/#{chapter.chapter_number}/download"

    assert_redirected_to library_series_path(series_slug: @series.to_param)
    assert_not FileAsset.exists?(file_asset.id)
  end

  def test_remove_download_shows_flash_message
    chapter = chapters(:one)

    delete "/sources/weeb-central/#{series_url}/chapters/#{chapter.chapter_number}/download"

    assert_redirected_to library_series_path(series_slug: @series.to_param)
    follow_redirect!

    assert_includes @response.body, "Download removed"
  end

  def test_cancel_download_cancels_queued_download
    chapter = chapters(:two)
    release = releases(:two)
    file_asset = file_assets(:two)
    file_asset.update!(download_status: "queued")

    post "/sources/weeb-central/#{series_url}/chapters/#{chapter.chapter_number}/cancel_download"

    assert_redirected_to library_series_path(series_slug: @series.to_param)
    file_asset.reload

    assert_equal "cancelled", file_asset.download_status
    assert_equal "Cancelled by user", file_asset.download_error
  end

  def test_cancel_download_cancels_downloading
    chapter = chapters(:two)
    release = releases(:two)
    file_asset = file_assets(:two)
    file_asset.update!(download_status: "downloading", pages_downloaded: 5, pages_expected: 10)

    post "/sources/weeb-central/#{series_url}/chapters/#{chapter.chapter_number}/cancel_download"

    assert_redirected_to library_series_path(series_slug: @series.to_param)
    file_asset.reload

    assert_equal "cancelled", file_asset.download_status
    assert_equal "Cancelled by user", file_asset.download_error
    assert_equal 0, file_asset.pages_downloaded
    assert_nil file_asset.pages_expected
  end

  test "canonical reader chooses replacement release while retaining chapter progress" do
    source = sources(:two)
    SeriesSource.create!(series: @series, source: source, source_series_id: "replacement")
    chapter = chapters(:two)
    release = chapter.releases.create!(source: source, format: "pages", source_url: "https://example.com/replacement/2")
    user_series_follows(:one).update!(source_priority: [ source.key ])
    progress = ChapterProgress.create!(user: users(:admin), chapter: chapter, page_index: 2, page_count: 3, status: "in_progress", progressed_at: Time.current)
    adapter = FakeAdapter.new(pages: (1..3).map { |number| Scrapers::ResultTypes::Page.new(index: number, url: "https://example.com/image-#{number}.jpg") })
    requested_urls = []
    original_pages = adapter.method(:pages)
    adapter.define_singleton_method(:pages) { |url| requested_urls << url; original_pages.call(url) }

    with_adapter(adapter) do
      get chapter_public_path(public_id: chapter.public_id)

      assert_redirected_to source_series_chapter_path(source_slug: source.slug, series_slug: @series.to_param, chapter_identifier: chapter.public_id)
      follow_redirect!

      assert_response :success
    end

    assert_equal [ release.source_url ], requested_urls
    assert_equal 2, progress.reload.page_index
    assert_equal sources(:one), chapter.reload.source
  end

  test "replacement download uses its release URL and preserves the existing chapter" do
    source = sources(:two)
    SeriesSource.create!(series: @series, source: source, source_series_id: "replacement")
    chapter = chapters(:two)
    release = chapter.releases.create!(source: source, format: "pages", source_url: "https://example.com/replacement/2")

    assert_no_difference "Chapter.count" do
      post source_series_chapter_download_path(source_slug: source.slug, series_slug: @series.to_param, chapter_identifier: "2")
    end

    job = enqueued_jobs.find { |entry| entry[:job] == DownloadChapterJob }
    arguments = ActiveJob::Arguments.deserialize(job[:args])

    assert_equal release.source_url, arguments.first
    assert_equal source.key, arguments.last[:source_key]
    assert_equal "replacement", arguments.last[:source_series_id]
    assert_equal release.id, arguments.last[:release_id]
    assert_equal sources(:one), chapter.reload.source
  end

  test "canonical reader keeps using saved pages after a replacement is selected" do
    source = sources(:two)
    SeriesSource.create!(series: @series, source: source, source_series_id: "replacement")
    chapter = chapters(:one)
    chapter.releases.create!(source: source, format: "pages", source_url: "https://example.com/replacement/1")
    user_series_follows(:one).update!(source_priority: [ source.key ])

    get chapter_public_path(public_id: chapter.public_id)

    assert_redirected_to source_series_chapter_path(source_slug: sources(:one).slug, series_slug: @series.to_param, chapter_identifier: chapter.public_id)
  end

  private

  def enable_local_download_mode
    users(:admin).update!(local_downloads_enabled: "true")
  end

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
