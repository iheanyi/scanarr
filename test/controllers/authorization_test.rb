require "test_helper"

class AuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    sign_in_as(users(:member))
  end

  def test_member_cannot_access_admin_downloads
    get admin_downloads_path

    assert_redirected_to root_path
  end

  def test_member_cannot_access_admin_scrapers
    get admin_scrapers_path

    assert_redirected_to root_path
  end

  def test_member_cannot_access_admin_backups
    get admin_backups_path

    assert_redirected_to root_path
  end

  def test_member_cannot_access_admin_users
    get admin_users_path

    assert_redirected_to root_path
  end

  def test_member_cannot_access_admin_jobs_dashboard
    get "/admin/jobs"

    assert_redirected_to root_path
  end

  def test_member_cannot_enable_disable_sources
    source = sources(:one)
    patch settings_source_path(source_id: source.id), params: { enabled: "0" }

    assert_redirected_to root_path
  end

  def test_member_can_access_settings
    get settings_path

    assert_response :success
  end

  def test_member_can_access_library
    get library_path

    assert_response :success
  end

  def test_member_can_access_search
    get search_path

    assert_response :success
  end
end
