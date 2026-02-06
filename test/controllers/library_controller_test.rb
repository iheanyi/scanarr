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
end
