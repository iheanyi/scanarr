# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :require_user

  def show
    @user = current_user
    @sources = Source.order(:name)
  end

  def update
    @user = current_user

    if @user.update(user_preferences_params)
      respond_to do |format|
        format.html { redirect_to settings_path, notice: "Settings saved" }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("toast-container",
            UI::ToastComponent.new(message: "Settings saved", variant: :success))
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to settings_path, alert: "Could not save settings" }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("toast-container",
            UI::ToastComponent.new(message: "Could not save settings", variant: :danger))
        end
      end
    end
  end

  def update_source
    source = Source.find(params[:source_id])
    source.update!(enabled: params[:enabled] == "1")

    label = source.enabled? ? "enabled" : "disabled"
    respond_to do |format|
      format.html { redirect_to settings_path, notice: "#{source.name} #{label}" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("toast-container",
          UI::ToastComponent.new(message: "#{source.name} #{label}", variant: :success))
      end
    end
  end

  private

  def user_preferences_params
    params.require(:user).permit(
      :default_reading_style,
      :default_language,
      :default_download_policy,
      :default_check_interval_minutes,
      :notifications_enabled,
      :notification_auto_cleanup_days
    )
  end
end
