require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  def test_admin_can_list_users
    get admin_users_path

    assert_response :success
    assert_includes @response.body, "admin"
  end

  def test_admin_can_create_member_user
    assert_difference "User.count", 1 do
      post admin_users_path, params: {
        user: {
          username: "newmember",
          email: "newmember@test.com",
          password: "testpassword123",
          password_confirmation: "testpassword123",
          role: "member"
        }
      }
    end

    assert_redirected_to admin_users_path
    new_user = User.find_by(username: "newmember")

    assert_predicate new_user, :member?
  end

  def test_admin_can_create_admin_user
    post admin_users_path, params: {
      user: {
        username: "newadmin",
        email: "newadmin@test.com",
        password: "testpassword123",
        password_confirmation: "testpassword123",
        role: "admin"
      }
    }

    assert_redirected_to admin_users_path
    new_user = User.find_by(username: "newadmin")

    assert_predicate new_user, :admin?
  end

  def test_admin_can_delete_other_users
    other = users(:member)

    assert_difference "User.count", -1 do
      delete admin_user_path(other)
    end

    assert_redirected_to admin_users_path
  end

  def test_admin_cannot_delete_self
    delete admin_user_path(@test_user)

    assert_redirected_to admin_users_path
    assert_includes flash[:alert], "cannot delete yourself"
    assert User.exists?(@test_user.id)
  end

  def test_member_gets_redirected_from_user_management
    sign_out
    sign_in_as(users(:member))

    get admin_users_path

    assert_redirected_to root_path
  end
end
