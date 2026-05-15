module Admin
  class UsersController < AdminController
    before_action :set_user, only: :destroy

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
      if @user == current_user
        respond_with_toast(
          redirect_path: admin_users_path,
          message: "You cannot delete yourself",
          variant: :warning
        )
        return
      end
      @user.destroy!

      respond_with_toast(
        redirect_path: admin_users_path,
        message: "#{@user.username} deleted",
        variant: :success,
        streams: [
          turbo_stream.remove(ActionView::RecordIdentifier.dom_id(@user))
        ]
      )
    end

    private

    def set_user
      @user = User.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      respond_with_toast(
        redirect_path: admin_users_path,
        message: "User not found",
        variant: :danger,
        status: :not_found,
        turbo_redirect: true
      )
      nil
    end

    def user_params
      params.require(:user).permit(:username, :email, :password, :password_confirmation)
    end
  end
end
