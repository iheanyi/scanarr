require "test_helper"

class LibraryControllerTest < ActionDispatch::IntegrationTest
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
      assert_select "select[name='status'] option", text: "Completed"
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
