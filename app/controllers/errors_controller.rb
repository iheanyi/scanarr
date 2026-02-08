# frozen_string_literal: true

class ErrorsController < ApplicationController
  skip_before_action :authenticate!

  def not_found
    render "errors/not_found", status: :not_found, layout: "application"
  end

  def unprocessable_entity
    render "errors/unprocessable_entity", status: :unprocessable_entity, layout: "application"
  end

  def internal_server_error
    render "errors/internal_server_error", status: :internal_server_error, layout: "application"
  end
end
