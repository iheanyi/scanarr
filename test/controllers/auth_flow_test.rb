require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
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
