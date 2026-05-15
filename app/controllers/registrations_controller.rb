# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 10.minutes, only: :create, with: :rate_limit_exceeded

  layout "minimal"

  before_action :redirect_if_authenticated
  before_action :require_registration_enabled

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    @user.role = :member

    if @user.save
      start_new_session_for(@user)
      redirect_to root_path, notice: "Welcome to Scanarr!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_authenticated
    resume_session
    redirect_to root_path if authenticated?
  end

  def require_registration_enabled
    unless SiteSetting.registration_enabled?
      redirect_to login_path, alert: "Registration is currently disabled."
    end
  end

  def registration_params
    params.require(:user).permit(:username, :email, :password, :password_confirmation)
  end
end
