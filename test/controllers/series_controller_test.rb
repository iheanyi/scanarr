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
    assert_includes @response.body, "/sources/weeb-central/#{series_url(series)}"
  end

  def test_show_returns_success
    series = series(:one)
    get "/sources/weeb-central/#{series_url(series)}"
    assert_response :success
    assert_includes @response.body, "Chapter 1"
    assert_includes @response.body, "/sources/weeb-central/#{series_url(series)}/chapters/1"
  end

  def test_show_orders_chapters_numerically
    series = series(:one)
    source = sources(:one)
    Chapter.create!(series: series, source: source, chapter_number: "10", title: "Chapter 10")
    Chapter.create!(series: series, source: source, chapter_number: "10.5", title: "Chapter 10.5")
    Chapter.create!(series: series, source: source, chapter_number: "Extra", title: "Chapter 10 Extra")

    get "/sources/weeb-central/#{series_url(series)}"
    assert_response :success
    body = @response.body
    assert body.index(">Chapter 1</a>") < body.index(">Chapter 2</a>")
    assert body.index(">Chapter 2</a>") < body.index(">Chapter 10</a>")
    assert body.index(">Chapter 10</a>") < body.index(">Chapter Extra</a>")
    assert body.index(">Chapter Extra</a>") < body.index(">Chapter 10.5</a>")
  end

  def test_show_renders_progress_pill_for_signed_in_user
    # Auto-create admin user for progress tracking
    admin = User.find_or_create_by!(email: "admin@scanarr.local")
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

    get "/sources/weeb-central/#{series_url(series)}"
    assert_response :success
    assert_includes @response.body, "In Progress"
  end

  def test_show_displays_download_all_button
    series = series(:one)
    get "/sources/weeb-central/#{series_url(series)}"
    assert_response :success
    assert_includes @response.body, "Download All"
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
    assert_redirected_to "/sources/weeb-central/#{series_url(series)}"
    follow_redirect!
    assert_includes @response.body, "Queuing"
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
    assert_redirected_to "/sources/weeb-central/#{series_url(series)}"
  end

  def test_refresh_cover_redirects
    series = series(:one)
    series.update!(cover_url: "https://example.com/cover.jpg")

    post "/sources/weeb-central/#{series_url(series)}/refresh_cover"
    assert_redirected_to "/sources/weeb-central/#{series_url(series)}"
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
