require "test_helper"

class ReadingHistoryControllerTest < ActionDispatch::IntegrationTest
  def test_index_returns_success
    get "/history"

    assert_response :success
    assert_includes @response.body, "Reading History"
  end

  def test_index_shows_empty_state
    get "/history"

    assert_response :success
    assert_includes @response.body, "No reading history yet"
  end

  def test_index_with_reading_progress
    admin = users(:admin)
    chapter = chapters(:one)
    ChapterProgress.create!(
      user: admin,
      chapter: chapter,
      page_index: 5,
      page_count: 10,
      status: "in_progress",
      progressed_at: Time.current
    )

    get "/history"

    assert_response :success
    assert_includes @response.body, chapter.series.canonical_title
  end

  def test_index_filters_by_status
    admin = users(:admin)
    chapter = chapters(:one)
    ChapterProgress.create!(
      user: admin,
      chapter: chapter,
      page_index: 10,
      page_count: 10,
      status: "completed",
      progressed_at: Time.current
    )

    get "/history", params: { status: "completed" }

    assert_response :success
    assert_includes @response.body, chapter.series.canonical_title
  end

  def test_index_empty_filter_result
    get "/history", params: { status: "completed" }

    assert_response :success
    assert_includes @response.body, "No completed chapters"
  end
end
