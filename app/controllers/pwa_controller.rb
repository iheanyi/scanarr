# frozen_string_literal: true

class PwaController < ApplicationController
  allow_unauthenticated_access only: %i[manifest service_worker offline]
  skip_forgery_protection only: :service_worker

  def manifest
    expires_in 12.hours, public: true
    render template: "pwa/manifest", formats: [ :json ], layout: false, content_type: "application/manifest+json"
  end

  def service_worker
    response.headers["Service-Worker-Allowed"] = "/"
    response.headers["Cache-Control"] = "no-store"
    render template: "pwa/service_worker", formats: [ :js ], layout: false, content_type: "application/javascript"
  end

  def offline
    render layout: "minimal"
  end
end
