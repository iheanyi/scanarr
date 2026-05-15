require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  def test_login_page_uses_default_theme
    sign_out

    get login_path

    assert_response :success
    assert_includes @response.body, 'data-scanarr-theme="signal-coral"'
  end

  def test_login_with_valid_credentials
    sign_out
    post login_path, params: { username: "admin", password: "testpassword123" }

    assert_redirected_to root_url
    follow_redirect!

    assert_response :success
  end

  def test_login_with_invalid_credentials
    sign_out
    post login_path, params: { username: "admin", password: "wrongpassword" }

    assert_response :unprocessable_entity
    assert_includes @response.body, "Invalid username or password"
  end

  def test_login_rate_limits_repeated_attempts
    sign_out

    10.times do
      post login_path, params: { username: "admin", password: "wrongpassword" }

      assert_response :unprocessable_entity
    end

    post login_path, params: { username: "admin", password: "wrongpassword" }

    assert_response :too_many_requests
  end

  def test_api_key_auth_valid
    sign_out
    get library_path, headers: { "X-Api-Key" => users(:admin).api_key }

    assert_response :success
  end

  def test_api_key_auth_invalid
    sign_out
    get library_path, headers: { "X-Api-Key" => "invalid_key" }

    assert_response :unauthorized
  end

  def test_invalid_api_key_does_not_fall_back_to_cookie_session
    get library_path, headers: { "X-Api-Key" => "invalid_key" }

    assert_response :unauthorized
  end

  def test_unauthenticated_redirects_to_login
    sign_out
    get library_path

    assert_redirected_to login_path
  end

  def test_logout_clears_session
    get library_path

    assert_response :success

    delete logout_path

    assert_redirected_to login_path

    get library_path

    assert_redirected_to login_path
  end
end
