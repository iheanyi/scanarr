require "test_helper"

class OfflineLibraryControllerTest < ActionDispatch::IntegrationTest
  setup do
    users(:admin).update!(local_downloads_enabled: "true")
    sign_in_as users(:admin)
  end

  def test_show_renders_shell
    get offline_library_path

    assert_response :success
    assert_select "[data-controller='offline-library']"
    assert_select "h1", text: "Offline Library"
  end

  def test_show_requires_authentication
    sign_out
    get offline_library_path

    assert_response :redirect
  end

  def test_show_requires_local_downloads_toggle
    users(:admin).update!(local_downloads_enabled: "false")

    get offline_library_path

    assert_response :forbidden
  end
end
