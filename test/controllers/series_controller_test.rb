require "test_helper"

class SeriesControllerTest < ActionDispatch::IntegrationTest
  def series_url(series)
    "#{series.public_id}-#{series.slug}"
  end

  def test_index_returns_success
    series = series(:one)
    get "/sources/weeb-central"

    assert_response :success
    assert_includes @response.body, "One Piece"
    assert_includes @response.body, library_series_path(series_slug: series.to_param)
  end

  def test_index_series_links_escape_turbo_frame
    series = series(:one)
    get "/sources/weeb-central"

    assert_response :success
    assert_select %(turbo-frame#series-content a[href="#{library_series_path(series_slug: series.to_param)}"][data-turbo-frame="_top"]), minimum: 1
  end

  def test_series_turbo_frame_links_always_declare_navigation_target
    get "/sources/weeb-central"

    assert_response :success
    assert_select "turbo-frame#series-content a[href]:not([href^='#']):not([data-turbo-frame])", 0
  end

  def test_index_sort_select_auto_submits_on_change
    get "/sources/weeb-central"

    assert_response :success
    assert_select "turbo-frame#series-content form select[name='sort_by'][data-action='change->auto-submit#submit']"
  end

  def test_show_redirects_to_library_canonical_path
    series = series(:one)
    get "/sources/weeb-central/#{series_url(series)}"

    assert_redirected_to library_series_path(series_slug: series.to_param)
  end

  def test_show_from_library_route_reuses_series_template
    series = series(:one)
    get library_series_path(series_slug: series.to_param)

    assert_response :success
    assert_includes @response.body, "Chapter 1"
    assert_includes @response.body, "/sources/weeb-central/#{series_url(series)}/chapters/1"
  end

  def test_show_empty_state_suggests_source_migration_when_no_chapters
    source = sources(:one)
    series = Series.create!(
      canonical_title: "No Chapters Yet",
      public_id: "seriespub999",
      slug: "no-chapters-yet"
    )
    SeriesSource.create!(series: series, source: source, source_series_id: "NO_CHAPTERS_001")

    get library_series_path(series_slug: series.to_param)

    assert_response :success
    assert_includes @response.body, "No chapters available from this source yet"
    assert_includes @response.body, library_series_migration_path(series_slug: series.to_param, from_source_id: source.id)
    assert_includes @response.body, source_search_path(source_slug: source.slug, q: series.canonical_title)
  end

  def test_show_orders_chapters_numerically
    series = series(:one)
    source = sources(:one)
    Chapter.create!(series: series, source: source, chapter_number: "10", title: "Chapter 10")
    Chapter.create!(series: series, source: source, chapter_number: "10.5", title: "Chapter 10.5")
    Chapter.create!(series: series, source: source, chapter_number: "Extra", title: "Chapter 10 Extra")

    get library_series_path(series_slug: series.to_param)

    assert_response :success
    body = @response.body

    assert_operator body.index(">Chapter 1</a>"), :<, body.index(">Chapter 2</a>")
    assert_operator body.index(">Chapter 2</a>"), :<, body.index(">Chapter 10</a>")
    assert_operator body.index(">Chapter 10</a>"), :<, body.index(">Chapter Extra</a>")
    assert_operator body.index(">Chapter Extra</a>"), :<, body.index(">Chapter 10.5</a>")
  end

  def test_show_renders_progress_pill_for_signed_in_user
    admin = users(:admin)
    series = series(:one)
    chapter = chapters(:one)
    ChapterProgress.create!(
      user: admin,
      chapter: chapter,
      page_index: 1,
      page_count: 2,
      status: "in_progress",
      progressed_at: Time.current
    )

    get library_series_path(series_slug: series.to_param)

    assert_response :success
    assert_includes @response.body, "In Progress"
  end

  def test_show_renders_failed_download_error_dialog
    file_assets(:one).update!(download_status: "failed")
    series = series(:one)
    chapter = chapters(:one)
    release = chapter.releases.create!(source: sources(:one), format: "pages", source_url: chapter.source_url)
    release.create_file_asset!(
      format: "pages",
      download_status: "failed",
      download_error: "NameError: uninitialized constant BaseAdapter::HttpClient"
    )

    get library_series_path(series_slug: series.to_param)

    assert_response :success
    progress_id = dom_id(chapter, :progress)
    dialog_id = dom_id(chapter, :download_error)
    dialog_title_id = dom_id(chapter, :download_error_title)
    dialog_body_id = dom_id(chapter, :download_error_body)

    assert_select "details.scanarr-panel-error-details", 0
    assert_select(
      "button##{progress_id}[aria-haspopup='dialog'][aria-controls='#{dialog_id}']",
      /NameError: uninitialized constant BaseAdapter::/
    )
    assert_select(
      "dialog##{dialog_id}.scanarr-panel-error-dialog[aria-labelledby='#{dialog_title_id}'][aria-describedby='#{dialog_body_id}']"
    ) do
      assert_select "button[aria-label='Close download error']"
      assert_select "pre##{dialog_body_id} code", "NameError: uninitialized constant BaseAdapter::HttpClient"
    end
  end

  def test_show_renders_download_progress_with_page_counts
    series = series(:one)
    chapter = chapters(:two)
    file_asset = file_assets(:two)
    file_asset.update!(
      download_status: "downloading",
      pages_downloaded: 4,
      pages_expected: 10
    )

    get library_series_path(series_slug: series.to_param)

    assert_response :success
    assert_includes @response.body, "Downloading 4/10 (40%)"
    assert_select(
      "span##{dom_id(chapter, :download_progress_bar)}[role='progressbar'][aria-valuenow='4'][aria-valuemax='10']"
    )
  end

  def test_show_renders_queued_download_state
    series = series(:one)
    file_assets(:two).update!(download_status: "queued", pages_downloaded: 0, pages_expected: nil)

    get library_series_path(series_slug: series.to_param)

    assert_response :success
    assert_includes @response.body, "Queued for download"
  end

  def test_show_displays_download_all_button
    series = series(:one)
    get library_series_path(series_slug: series.to_param)

    assert_response :success
    assert_includes @response.body, "Download All"
  end

  def test_show_displays_start_reading_when_no_progress
    series = series(:one)
    chapter = chapters(:one)

    get library_series_path(series_slug: series.to_param)

    assert_response :success
    assert_includes @response.body, "Start reading"
    assert_includes @response.body, source_series_chapter_path(
      source_slug: sources(:one).slug,
      series_slug: series.to_param,
      chapter_identifier: chapter.chapter_number
    )
  end

  def test_show_displays_continue_reading_when_progress_exists
    series = series(:one)
    chapter = chapters(:two)
    user = users(:admin)
    ChapterProgress.create!(
      user: user,
      chapter: chapter,
      page_index: 3,
      page_count: 20,
      status: "in_progress",
      progressed_at: Time.current
    )

    get library_series_path(series_slug: series.to_param)

    assert_response :success
    assert_includes @response.body, "Continue reading"
    assert_includes @response.body, source_series_chapter_path(
      source_slug: sources(:one).slug,
      series_slug: series.to_param,
      chapter_identifier: chapter.chapter_number
    )
  end

  def test_download_all_enqueues_job
    series = series(:one)
    # Use chapter two which has "pending" status in fixtures
    chapter = chapters(:two)
    chapter.update!(source_url: "https://example.com/chapter/2")
    # Remove existing file_asset to test fresh download
    chapter.releases.each { |r| r.file_asset&.destroy }

    assert_enqueued_with(job: DownloadAllJob) do
      post "/sources/weeb-central/#{series_url(series)}/download_all"
    end
    assert_redirected_to library_series_path(series_slug: series.to_param)
    follow_redirect!

    assert_includes @response.body, "Queuing"
  end

  def test_cancel_all_downloads_returns_turbo_toast
    series = series(:one)

    post "/sources/weeb-central/#{series_url(series)}/cancel_all_downloads",
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_includes @response.body, "toast-container"
    assert_includes @response.body, "Cancelling downloads in background..."
  end

  def test_bulk_action_mark_read_returns_turbo_toast
    series = series(:one)
    chapter_ids = chapters(:one).id.to_s

    post "/sources/weeb-central/#{series_url(series)}/bulk_actions",
         params: { chapter_ids: chapter_ids, action_name: "mark_read" },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_includes @response.body, "toast-container"
    assert_includes @response.body, "Marked 1 chapter(s) as read"
  end

  def test_download_all_skips_already_complete_chapters
    series = series(:one)
    chapter = chapters(:one)
    chapter.update!(source_url: "https://example.com/chapter/1")
    release = chapter.releases.create!(source: sources(:one), format: "pages", source_url: chapter.source_url)
    release.create_file_asset!(format: "pages", download_status: "complete")

    assert_no_enqueued_jobs(only: DownloadChapterJob) do
      post "/sources/weeb-central/#{series_url(series)}/download_all"
    end
    assert_redirected_to library_series_path(series_slug: series.to_param)
  end

  def test_refresh_cover_redirects
    series = series(:one)
    series.update!(cover_url: "https://example.com/cover.jpg")

    post "/sources/weeb-central/#{series_url(series)}/refresh_cover"

    assert_redirected_to library_series_path(series_slug: series.to_param)
  end

  def test_to_param_format
    series = series(:one)

    assert_equal "#{series.public_id}-#{series.slug}", series.to_param
  end

  def test_find_by_param_extracts_public_id
    series = series(:one)
    found = Series.find_by_param!(series.to_param)

    assert_equal series, found
  end
end
