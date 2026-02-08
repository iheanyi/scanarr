class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  layout "minimal"

  def new
    redirect_to root_path if authenticated?
  end

  def create
    if (user = User.authenticate_by(username: params[:username], password: params[:password]))
      start_new_session_for(user)
      redirect_to after_authentication_url, notice: "Welcome to Scanarr!"
    else
      flash.now[:alert] = "Invalid username or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to login_path, notice: "You have been logged out"
  end
end
