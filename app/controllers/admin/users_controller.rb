module Admin
  class UsersController < ApplicationController
    before_action :require_admin

    def index
      @users = User.order(:created_at)
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)
      @user.role = params[:user][:role] || :member

      if @user.save
        redirect_to admin_users_path, notice: "#{@user.username} created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      user = User.find(params[:id])
      if user == current_user
        redirect_to admin_users_path, alert: "You cannot delete yourself"
        return
      end
      user.destroy!
      redirect_to admin_users_path, notice: "#{user.username} deleted"
    end

    private

    def user_params
      params.require(:user).permit(:username, :email, :password, :password_confirmation, :role)
    end
  end
end
