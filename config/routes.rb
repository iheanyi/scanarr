Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Authentication
  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  get "/design-system", to: "design_system#show", as: :design_system

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "sources#index"
  get "/library", to: "library#index", as: :library
  get "/calendar", to: "calendar#index", as: :calendar
  resources :follows, only: [ :create, :update, :destroy ]

  # Notifications
  resources :notifications, only: [ :index ] do
    member do
      post :mark_read
    end
    collection do
      post :mark_all_read
    end
  end
  get "/search", to: "search#index", as: :search
  get "/sources/:source_slug/search", to: "sources#search", as: :source_search
  get "/sources/:source_slug/browse", to: "sources#browse", as: :source_browse
  get "/sources/:source_slug/preview", to: "sources#preview", as: :source_preview
  post "/sources/:source_slug/import", to: "sources#import", as: :source_import
  get "/sources/:source_slug", to: "series#index", as: :source_series_index
  get "/sources/:source_slug/:series_slug", to: "series#show", as: :source_series
  patch "/sources/:source_slug/:series_slug", to: "series#update", as: :source_series_update
  post "/sources/:source_slug/:series_slug/download_all", to: "series#download_all", as: :source_series_download_all
  post "/sources/:source_slug/:series_slug/refresh_cover", to: "series#refresh_cover", as: :source_series_refresh_cover
  delete "/sources/:source_slug/:series_slug/remove_all_downloads", to: "series#remove_all_downloads", as: :source_series_remove_all_downloads
  post "/sources/:source_slug/:series_slug/cancel_all_downloads", to: "series#cancel_all_downloads", as: :source_series_cancel_all_downloads
  post "/sources/:source_slug/:series_slug/refresh_metadata", to: "series#refresh_metadata", as: :source_series_refresh_metadata
  get "/chapters/:public_id", to: "chapters#redirect", as: :chapter_public
  get "/sources/:source_slug/:series_slug/chapters/:chapter_identifier", to: "chapters#show", as: :source_series_chapter
  patch "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/progress",
        to: "chapters#update_progress",
        as: :source_series_chapter_progress
  post "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/download",
       to: "chapters#enqueue_download",
       as: :source_series_chapter_download
  delete "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/download",
         to: "chapters#remove_download",
         as: :source_series_chapter_remove_download

  post "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/cancel_download",
       to: "chapters#cancel_download",
       as: :source_series_chapter_cancel_download

  namespace :admin do
    get "scrapers", to: "scrapers#index", as: :scrapers
    post "scrapers/:source_id/smoke", to: "scrapers#run_smoke", as: :scraper_smoke
    get "downloads", to: "downloads#index", as: :downloads
    post "downloads/refresh_all_covers", to: "downloads#refresh_all_covers", as: :refresh_all_covers
    post "downloads/:id/restart", to: "downloads#restart", as: :download_restart
    post "downloads/restart_all_failed", to: "downloads#restart_all_failed", as: :restart_all_failed_downloads
    post "downloads/restart_all_stuck", to: "downloads#restart_all_stuck", as: :restart_all_stuck_downloads
  end

  # Mission Control for SolidQueue job monitoring
  mount MissionControl::Jobs::Engine, at: "/admin/jobs"
end
