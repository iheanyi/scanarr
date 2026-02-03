class SessionsController < ApplicationController
  skip_before_action :authenticate!, only: %i[new create]
  layout "minimal"

  def new
    redirect_to root_path if authenticated?
  end

  def create
    if valid_credentials?(params[:username], params[:password])
      session[:authenticated] = true
      session[:authenticated_at] = Time.current.to_i
      redirect_to root_path, notice: "Welcome to Scanarr!"
    else
      flash.now[:alert] = "Invalid username or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "You have been logged out"
  end
end
