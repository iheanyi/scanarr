require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  # Override the default setup that signs in — setup tests need unauthenticated state
  setup do
    sign_out
    UserSeriesFollow.delete_all
    NewChapterNotification.delete_all
    ChapterProgress.delete_all
    Session.delete_all
    User.delete_all
  end

  def test_renders_setup_when_no_users_exist
    get setup_path

    assert_response :success
    assert_includes @response.body, "Create your admin account"
  end

  def test_creates_admin_with_proper_credentials
    post setup_path, params: {
      user: {
        username: "myadmin",
        email: "admin@test.com",
        password: "securepassword123",
        password_confirmation: "securepassword123"
      }
    }

    assert_redirected_to root_path
    user = User.last

    assert_equal "myadmin", user.username
    assert_predicate user, :admin?
    assert_predicate user.api_key, :present?
    assert user.authenticate("securepassword123")
  end

  def test_upgrades_existing_phantom_user
    User.insert!({
      email: "admin@scanarr.local",
      username: "phantom_admin",
      api_key: "scanarr_test_phantom_key_000000000000000",
      role: User.roles[:admin],
      created_at: Time.current,
      updated_at: Time.current
    })
    phantom = User.find_by!(email: "admin@scanarr.local")

    post setup_path, params: {
      user: {
        username: "upgraded_admin",
        email: "admin@scanarr.local",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_redirected_to root_path
    phantom.reload

    assert_equal "upgraded_admin", phantom.username
    assert phantom.authenticate("newpassword123")
    assert_predicate phantom, :admin?
    assert_equal 1, User.count
  end

  def test_redirects_if_setup_already_complete
    User.create!(
      email: "admin@scanarr.local",
      username: "admin",
      password: "testpassword123",
      role: :admin
    )

    get setup_path

    assert_redirected_to root_path
  end

  def test_validates_password_length
    post setup_path, params: {
      user: {
        username: "admin",
        email: "admin@test.com",
        password: "short",
        password_confirmation: "short"
      }
    }

    assert_response :unprocessable_entity
    assert_equal 0, User.where.not(password_digest: nil).count
  end

  def test_rate_limits_repeated_setup_attempts
    5.times do
      post setup_path, params: {
        user: {
          username: "admin",
          email: "admin@test.com",
          password: "short",
          password_confirmation: "short"
        }
      }

      assert_response :unprocessable_entity
    end

    post setup_path, params: {
      user: {
        username: "admin",
        email: "admin@test.com",
        password: "short",
        password_confirmation: "short"
      }
    }

    assert_response :too_many_requests
  end
end
