module SessionTestHelper
  def sign_in_as(user)
    post login_path, params: { username: user.username, password: "testpassword123" }
    follow_redirect!
  end

  def sign_out
    delete logout_path
  end
end
