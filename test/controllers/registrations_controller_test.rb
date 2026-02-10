require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    SiteSetting.instance.update!(registration_enabled: true)
  end

  def test_renders_registration_form
    get register_path

    assert_response :success
    assert_includes @response.body, "Create Account"
    assert_includes @response.body, "Username"
    assert_includes @response.body, "Email"
    assert_includes @response.body, "Password"
  end

  def test_creates_member_user_with_valid_params
    assert_difference "User.count", 1 do
      post register_path, params: {
        user: {
          username: "newuser",
          email: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    user = User.find_by(username: "newuser")

    assert_predicate user, :member?
    assert_redirected_to root_path
  end

  def test_created_user_is_always_member
    post register_path, params: {
      user: {
        username: "sneaky",
        email: "sneaky@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    user = User.find_by(username: "sneaky")

    assert_predicate user, :member?
    assert_not user.admin?
  end

  def test_shows_validation_errors_for_bad_params
    post register_path, params: {
      user: {
        username: "",
        email: "",
        password: "short",
        password_confirmation: "mismatch"
      }
    }

    assert_response :unprocessable_entity
    assert_includes @response.body, "Username"
  end

  def test_redirects_to_login_when_registration_disabled
    SiteSetting.instance.update!(registration_enabled: false)

    get register_path

    assert_redirected_to login_path
    follow_redirect!

    assert_includes @response.body, "Registration is currently disabled"
  end

  def test_redirects_to_root_when_already_authenticated
    sign_in_as(users(:admin))

    get register_path

    assert_redirected_to root_path
  end

  def test_post_redirects_to_login_when_registration_disabled
    SiteSetting.instance.update!(registration_enabled: false)

    post register_path, params: {
      user: {
        username: "blocked",
        email: "blocked@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    assert_redirected_to login_path

    assert_nil User.find_by(username: "blocked")
  end

  def test_login_page_shows_signup_link_when_registration_enabled
    get login_path

    assert_response :success
    assert_includes @response.body, "Sign up"
  end

  def test_login_page_hides_signup_link_when_registration_disabled
    SiteSetting.instance.update!(registration_enabled: false)

    get login_path

    assert_response :success
    assert_not_includes @response.body, "Sign up"
  end
end
