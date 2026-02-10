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
    user = User.find_by(email: "admin@scanarr.local")
    assert_equal "webtoon", user.default_reading_style
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

  def test_show_displays_administration_section_for_admin
    get settings_path

    assert_response :success
    assert_includes @response.body, "Administration"
    assert_includes @response.body, "Allow Registration"
  end

  def test_show_hides_administration_section_for_member
    sign_out
    sign_in_as(users(:member))

    get settings_path

    assert_response :success
    assert_not_includes @response.body, "Administration"
  end

  def test_admin_can_toggle_registration_off
    patch settings_site_path, params: { site_setting: { registration_enabled: "false" } }

    assert_not SiteSetting.registration_enabled?
  end

  def test_admin_can_toggle_registration_on
    SiteSetting.instance.update!(registration_enabled: false)

    patch settings_site_path, params: { site_setting: { registration_enabled: "true" } }

    assert_predicate SiteSetting, :registration_enabled?
  end

  def test_member_cannot_update_site_settings
    sign_out
    sign_in_as(users(:member))

    patch settings_site_path, params: { site_setting: { registration_enabled: "false" } }

    assert_redirected_to root_path
    assert_predicate SiteSetting, :registration_enabled?
  end

  def test_update_site_settings_via_turbo_stream
    patch settings_site_path,
      params: { site_setting: { registration_enabled: "false" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes @response.body, "Site settings saved"
  end

  def test_show_redirects_when_not_authenticated
    sign_out
    get settings_path

    assert_redirected_to login_path
  end
end
