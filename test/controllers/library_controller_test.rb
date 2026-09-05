require "test_helper"

class LibraryControllerTest < ActionDispatch::IntegrationTest
  test "home opens the library with the current user's latest unfinished chapter per series" do
    ChapterProgress.create!(user: @test_user, chapter: chapters(:one), page_index: 2, page_count: 20, status: "in_progress", progressed_at: 2.days.ago)
    ChapterProgress.create!(user: @test_user, chapter: chapters(:two), page_index: 7, page_count: 20, status: "in_progress", progressed_at: 1.day.ago)
    ChapterProgress.create!(user: users(:member), chapter: chapters(:one), page_index: 10, page_count: 20, status: "in_progress", progressed_at: Time.current)

    get root_path

    assert_response :success
    assert_select "h1", "Library"
    assert_select "section[aria-labelledby='continue-reading-heading']" do
      assert_select "a[aria-label^='Continue ']", count: 1
      assert_select "a[href$='/chapters/#{chapters(:two).public_id}']"
      assert_select "p", text: "Page 7 of 20"
    end
  end

  test "library has no continue shelf for completed reading" do
    ChapterProgress.create!(user: @test_user, chapter: chapters(:one), page_index: 20, page_count: 20, status: "completed", progressed_at: Time.current)

    get library_path

    assert_select "#continue-reading-heading", count: 0
  end

  test "filter response keeps controls random action and empty reset together" do
    get library_path(status: "following", q: "No matching manga"), headers: { "Turbo-Frame" => "library-content" }

    assert_response :success
    assert_select "turbo-frame#library-content[data-turbo-action='advance']" do
      assert_select "input[name=q][value='No matching manga']"
      assert_select "select[name=sort_by] option[value=recently_updated]"
      assert_select "a[href*='/library/random'][href*='status=following'][data-turbo-frame='_top']"
      assert_select "a[href='/library'][data-turbo-frame='library-content']", text: "Clear filters"
    end
  end

  test "index shows all series" do
    get library_path

    assert_response :success
    assert_select "h1", "Library"
  end

  test "index filters by downloaded status" do
    get library_path(status: "downloaded")

    assert_response :success
  end

  test "index filters by in_progress status" do
    get library_path(status: "in_progress")

    assert_response :success
  end

  test "index filters by not_downloaded status" do
    get library_path(status: "not_downloaded")

    assert_response :success
  end

  test "index filters by not_started status" do
    get library_path(status: "not_started")

    assert_response :success
  end

  test "index filters by completed status" do
    get library_path(status: "completed")

    assert_response :success
  end

  test "index searches by title" do
    get library_path(q: "test")

    assert_response :success
  end

  test "index filters by following status" do
    get library_path(status: "following")

    assert_response :success
  end

  test "index filters by source_ids" do
    get library_path(source_ids: [ sources(:one).id ])

    assert_response :success
    assert_includes @response.body, "One Piece"
  end

  test "index filters by genres" do
    series(:one).update!(normalized_categories: [ "action" ])

    get library_path(genres: [ "action" ])

    assert_response :success
    assert_includes @response.body, "One Piece"
  end

  test "following view supports alphabetical sort" do
    get library_path(status: "following", sort_by: "alphabetical")

    assert_response :success
  end

  test "following view supports most_unread sort" do
    get library_path(status: "following", sort_by: "most_unread")

    assert_response :success
  end

  test "following view supports recently_updated sort" do
    get library_path(status: "following", sort_by: "recently_updated")

    assert_response :success
  end

  test "series links escape library turbo frame" do
    get library_path

    assert_response :success

    series = series(:one)
    series_url = library_series_path(series_slug: series.to_param)

    assert_select %(turbo-frame#library-content a[href="#{series_url}"][data-turbo-frame="_top"]), minimum: 1
  end

  test "library turbo frame links always declare navigation target" do
    get library_path

    assert_response :success
    assert_select "turbo-frame#library-content a[href]:not([href^='#']):not([data-turbo-frame])", 0
  end

  test "index renders live filter controls and random action" do
    series(:one).update!(normalized_categories: [ "action" ])

    get library_path

    assert_response :success
    assert_select %(form[action="#{library_path}"][data-turbo-frame="library-content"]) do
      assert_select "select[name='status'] option", text: "All"
      assert_select "select[name='status'] option", text: "Not Started"
      assert_select "select[name='status'] option", text: "Has read chapters"
      assert_select "input[type='checkbox'][name='source_ids[]']"
      assert_select "input[type='checkbox'][name='genres[]'][value='action']"
      assert_select "input[name='q'][placeholder='Filter series...'][data-action='input->auto-submit#submitDebounced']"
    end
    assert_select %(a[href^="#{library_random_path}"]), minimum: 1
  end

  test "random redirects to a library series page" do
    get library_random_path

    assert_response :redirect
    assert_match(%r{\Ahttp://www\.example\.com/library/[a-z0-9-]+\z}, response.location)
  end
end
