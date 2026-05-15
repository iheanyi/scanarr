# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :require_user
  before_action :require_admin, only: %i[update_source update_site_settings]

  def show
    @user = current_user
    @sources = Source.order(:name)
    @site_settings = SiteSetting.instance if current_user.admin?
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

  def update_password
    @user = current_user

    unless @user.authenticate(params[:current_password])
      respond_to do |format|
        format.html { redirect_to settings_path, alert: "Current password is incorrect" }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("toast-container",
            UI::ToastComponent.new(message: "Current password is incorrect", variant: :danger))
        end
      end
      return
    end

    if @user.update(password: params[:new_password], password_confirmation: params[:new_password_confirmation])
      respond_to do |format|
        format.html { redirect_to settings_path, notice: "Password updated" }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("toast-container",
            UI::ToastComponent.new(message: "Password updated", variant: :success))
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to settings_path, alert: @user.errors.full_messages.join(", ") }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("toast-container",
            UI::ToastComponent.new(message: @user.errors.full_messages.join(", "), variant: :danger))
        end
      end
    end
  end

  def regenerate_api_key
    current_user.regenerate_api_key!

    respond_to do |format|
      format.html { redirect_to settings_path, notice: "API key regenerated" }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("api-key-display", partial: "settings/api_key", locals: { user: current_user }),
          turbo_stream.append("toast-container",
            UI::ToastComponent.new(message: "API key regenerated", variant: :success))
        ]
      end
    end
  end

  def update_site_settings
    site_settings = SiteSetting.instance
    site_settings.update!(site_settings_params)

    respond_to do |format|
      format.html { redirect_to settings_path, notice: "Site settings saved" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("toast-container",
          UI::ToastComponent.new(message: "Site settings saved", variant: :success))
      end
    end
  end

  def update_source_priority
    priority = JSON.parse(params[:source_priority]) rescue []
    current_user.update!(default_source_priority: priority)

    respond_to do |format|
      format.html { redirect_to settings_path, notice: "Source priority saved" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("toast-container",
          UI::ToastComponent.new(message: "Source priority saved", variant: :success))
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

  def site_settings_params
    params.require(:site_setting).permit(:registration_enabled)
  end

  def user_preferences_params
    permitted = params.require(:user).permit(
      :default_reading_style,
      :default_language,
      :default_download_policy,
      :default_check_interval_minutes,
      :local_downloads_enabled,
      :notifications_enabled,
      :notification_auto_cleanup_days,
      :theme
    )

    if permitted[:default_reading_style].present?
      permitted[:default_reading_style] = ReadingStyles.normalize(permitted[:default_reading_style])
    end

    if permitted[:theme].present?
      permitted[:theme] = ScanarrThemes.normalize(permitted[:theme])
    end

    permitted
  end
end
