class SetupController < ApplicationController
  allow_unauthenticated_access
  layout "minimal"

  before_action :redirect_if_setup_complete

  def new
    @user = User.first_or_initialize(email: "admin@scanarr.local")
  end

  def create
    # Find existing user by email or grab the first phantom user to upgrade
    @user = User.find_by(email: setup_params[:email]) || User.first_or_initialize
    @user.assign_attributes(setup_params)
    @user.role = :admin

    if @user.save
      start_new_session_for(@user)
      redirect_to root_path, notice: "Welcome to Scanarr! Your admin account has been created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_setup_complete
    redirect_to root_path if User.where.not(password_digest: nil).exists?
  end

  def setup_params
    params.require(:user).permit(:username, :email, :password, :password_confirmation)
  end
end
