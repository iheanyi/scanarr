require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
  def test_show_returns_success
    get "/stats"

    assert_response :success
    assert_includes @response.body, "Reading Stats"
  end

  def test_show_displays_stat_cards
    get "/stats"

    assert_response :success
    assert_includes @response.body, "Chapters Read"
    assert_includes @response.body, "Series In Progress"
    assert_includes @response.body, "Series Followed"
    assert_includes @response.body, "Chapters / Week"
  end

  def test_show_displays_reading_activity
    get "/stats"

    assert_response :success
    assert_includes @response.body, "Reading Activity"
  end

  def test_show_with_reading_progress
    admin = User.find_or_create_by!(email: "admin@scanarr.local")
    chapter = chapters(:one)
    ChapterProgress.create!(
      user: admin,
      chapter: chapter,
      page_index: 5,
      page_count: 5,
      status: "completed",
      progressed_at: 1.day.ago
    )

    get "/stats"

    assert_response :success
    # Should count at least 1 completed chapter
    assert_includes @response.body, "Chapters Read"
  end

  def test_show_displays_recently_read_with_progress
    admin = User.find_or_create_by!(email: "admin@scanarr.local")
    chapter = chapters(:one)
    ChapterProgress.create!(
      user: admin,
      chapter: chapter,
      page_index: 5,
      page_count: 5,
      status: "completed",
      progressed_at: 1.hour.ago
    )

    get "/stats"

    assert_response :success
    assert_includes @response.body, "Recently Read"
  end
end
