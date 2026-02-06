# frozen_string_literal: true

require "test_helper"

class CalendarControllerTest < ActionDispatch::IntegrationTest
  test "index renders for week view" do
    get calendar_path(view: "week")

    assert_response :success
  end

  test "index renders for month view" do
    get calendar_path(view: "month")

    assert_response :success
  end

  test "index renders for recent view" do
    get calendar_path(view: "recent")

    assert_response :success
  end

  test "index renders with source filter" do
    source = sources(:one)
    get calendar_path(view: "week", source: source.slug)

    assert_response :success
  end

  test "index renders with week offset" do
    get calendar_path(view: "week", week_offset: -1)

    assert_response :success
  end
end
