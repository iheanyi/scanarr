class ApplicationController < ActionController::Base
  include Authentication

  protect_from_forgery with: :exception, unless: -> { request.headers["X-Api-Key"].present? }

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::RoutingError, with: :render_not_found

  helper_method :current_notifications, :unread_notification_count, :chapter_identifier

  private

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

  def current_notifications
    return [] unless current_user
    @current_notifications ||= current_user.new_chapter_notifications
      .includes(chapter: :series)
      .unread
      .recent
      .order(created_at: :desc)
      .limit(10)
  end

  def unread_notification_count
    return 0 unless current_user
    @unread_notification_count ||= current_user.new_chapter_notifications.unread.count
  end

  def chapter_identifier(chapter)
    chapter.chapter_number.presence || chapter.public_id
  end
end
