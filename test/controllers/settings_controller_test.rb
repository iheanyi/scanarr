require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def test_show_returns_success
    get settings_path

    assert_response :success
    assert_includes @response.body, "Settings"
    assert_includes @response.body, "Reading Preferences"
    assert_includes @response.body, "Download Defaults"
    assert_includes @response.body, "Notifications"
    assert_includes @response.body, "Sources"
    assert_includes @response.body, "Data Management"
  end

  def test_update_reading_style
    patch settings_path, params: { user: { default_reading_style: "right_to_left" } }

    assert_redirected_to settings_path
    user = User.find_by(email: "admin@scanarr.local")

    assert_equal "right_to_left", user.default_reading_style
  end

  def test_update_download_policy
    patch settings_path, params: { user: { default_download_policy: "auto_download" } }

    assert_redirected_to settings_path
    user = User.find_by(email: "admin@scanarr.local")

    assert_equal "auto_download", user.default_download_policy
  end

  def test_update_notifications_enabled
    patch settings_path, params: { user: { notifications_enabled: "false" } }

    assert_redirected_to settings_path
    user = User.find_by(email: "admin@scanarr.local")

    assert_not user.notifications_enabled?
  end

  def test_update_via_turbo_stream
    patch settings_path,
      params: { user: { default_reading_style: "long_strip" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes @response.body, "Settings saved"
  end

  def test_update_source_enable
    source = sources(:two)

    assert_not source.enabled?

    patch settings_source_path(source_id: source.id), params: { enabled: "1" }

    assert_redirected_to settings_path
    assert_predicate source.reload, :enabled?
  end

  def test_update_source_disable
    source = sources(:one)

    assert_predicate source, :enabled?

    patch settings_source_path(source_id: source.id), params: { enabled: "0" }

    assert_redirected_to settings_path
    assert_not source.reload.enabled?
  end

  def test_show_redirects_when_no_user
    # Simulate unauthenticated request by skipping auth headers
    get settings_path, headers: { "HTTP_AUTHORIZATION" => nil }

    assert_redirected_to login_path
  end
end
