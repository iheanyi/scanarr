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

  test "index searches by title" do
    get library_path(q: "test")

    assert_response :success
  end

  test "index filters by following status" do
    get library_path(status: "following")

    assert_response :success
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

    source = sources(:one)
    series = series(:one)
    series_url = source_series_path(source_slug: source.slug, series_slug: series.to_param)

    assert_select %(turbo-frame#library-content a[href="#{series_url}"][data-turbo-frame="_top"]), minimum: 1
  end
end
