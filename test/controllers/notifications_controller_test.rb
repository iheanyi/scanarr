require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  def test_mark_read_returns_turbo_toast_and_marks_notification_read
    notification = NewChapterNotification.create!(
      user: @test_user,
      chapter: chapters(:one),
      read: false
    )

    post mark_read_notification_path(notification), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_predicate notification.reload, :read?
    assert_includes @response.body, "toast-container"
    assert_includes @response.body, "Notification marked as read"
    assert_select "turbo-stream[action=replace][targets='[data-notification-count]']"
  end

  def test_mark_all_read_returns_turbo_toast_and_marks_all_read
    first = NewChapterNotification.create!(user: @test_user, chapter: chapters(:one), read: false)
    second = NewChapterNotification.create!(user: @test_user, chapter: chapters(:two), read: false)

    post mark_all_read_notifications_path, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_predicate first.reload, :read?
    assert_predicate second.reload, :read?
    assert_includes @response.body, "toast-container"
    assert_includes @response.body, "All notifications marked as read"
    assert_select "turbo-stream[action=replace][targets='[data-notification-count]']"
  end

  def test_mark_read_missing_notification_turbo_request_redirects_with_flash
    post mark_read_notification_path("missing-notification-id"),
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_redirected_to notifications_path
    assert_equal "Notification not found", flash[:alert]
  end
end
