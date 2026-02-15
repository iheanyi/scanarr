class ApplicationController < ActionController::Base
  include Authentication

  protect_from_forgery with: :exception, unless: -> { request.headers["X-Api-Key"].present? }

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::RoutingError, with: :render_not_found

  helper_method :current_notifications, :unread_notification_count, :chapter_identifier, :local_downloads_enabled?

  private

  def toast_stream(message, variant: :success)
    turbo_stream.append("toast-container", UI::ToastComponent.new(message: message, variant: variant))
  end

  def respond_with_toast(redirect_path:, message:, variant: :success, streams: [], status: :ok, turbo_redirect: false, turbo_redirect_status: :see_other)
    flash_key = variant.in?([ :success, :info ]) ? :notice : :alert

    respond_to do |format|
      format.html { redirect_to redirect_path, flash_key => message }
      format.turbo_stream do
        if turbo_redirect
          redirect_to redirect_path, flash_key => message, status: turbo_redirect_status
        else
          render turbo_stream: Array(streams) + [ toast_stream(message, variant: variant) ], status: status
        end
      end
    end
  end

  def render_not_found
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found, layout: "application" }
      format.turbo_stream { render "errors/not_found", status: :not_found, layout: "application", formats: [ :html ], content_type: "text/html" }
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.any { render "errors/not_found", status: :not_found, layout: "application", formats: [ :html ], content_type: "text/html" }
    end
  end

  def render_unprocessable
    respond_to do |format|
      format.html { render "errors/unprocessable_entity", status: :unprocessable_entity, layout: "application" }
      format.turbo_stream { render "errors/unprocessable_entity", status: :unprocessable_entity, layout: "application", formats: [ :html ], content_type: "text/html" }
      format.json { render json: { error: "Unprocessable request" }, status: :unprocessable_entity }
      format.any { render "errors/unprocessable_entity", status: :unprocessable_entity, layout: "application", formats: [ :html ], content_type: "text/html" }
    end
  end

  def render_internal_error
    respond_to do |format|
      format.html { render "errors/internal_server_error", status: :internal_server_error, layout: "application" }
      format.turbo_stream { render "errors/internal_server_error", status: :internal_server_error, layout: "application", formats: [ :html ], content_type: "text/html" }
      format.json { render json: { error: "Internal server error" }, status: :internal_server_error }
      format.any { render "errors/internal_server_error", status: :internal_server_error, layout: "application", formats: [ :html ], content_type: "text/html" }
    end
  end

  def require_user
    return if current_user
    redirect_to root_path, alert: "You must be logged in to access that page."
  end

  def local_downloads_enabled?
    return false unless current_user

    current_user.local_downloads_enabled?
  end

  def require_local_downloads_enabled
    return if local_downloads_enabled?

    render json: { error: "Local download mode is disabled for this account." }, status: :forbidden
  end

  def current_notifications
    return [] unless current_user
    @current_notifications ||= current_user.new_chapter_notifications
      .includes(chapter: { series: { cover_attachment: :blob } })
      .unread
      .recent
      .order(created_at: :desc)
      .limit(10)
      .to_a
  end

  def unread_notification_count
    return 0 unless current_user
    # Reuse already-loaded notifications to avoid a separate COUNT query
    if defined?(@current_notifications) && @current_notifications
      @current_notifications.size
    else
      @unread_notification_count ||= current_user.new_chapter_notifications.unread.count
    end
  end

  def chapter_identifier(chapter)
    chapter.chapter_number.presence || chapter.public_id
  end
end
