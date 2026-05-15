require "test_helper"

class UserTest < ActiveSupport::TestCase
  def test_requires_password_for_new_users
    user = User.new(email: "password-required@example.com", username: "password_required")

    assert_not user.valid?
    assert_includes user.errors[:password], "can't be blank"
  end

  def test_requires_matching_password_confirmation
    user = User.new(
      email: "password-mismatch@example.com",
      username: "password_mismatch",
      password: "testpassword123",
      password_confirmation: "differentpassword123"
    )

    assert_not user.valid?
    assert_includes user.errors[:password_confirmation], "doesn't match Password"
  end

  def test_rejects_passwords_longer_than_bcrypt_byte_limit
    user = User.new(
      email: "password-too-long@example.com",
      username: "password_too_long",
      password: "a" * 73,
      password_confirmation: "a" * 73
    )

    assert_not user.valid?
    assert_includes user.errors[:password], "is too long (maximum is 72 bytes)"
  end
end
