Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Setup wizard
  get "/setup", to: "setup#new", as: :setup
  post "/setup", to: "setup#create"

  # Authentication
  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  # Registration
  get "/register", to: "registrations#new", as: :register
  post "/register", to: "registrations#create"

  get "/design-system", to: "design_system#show", as: :design_system

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "sources#index"
  get "/library", to: "library#index", as: :library
  get "/library/random", to: "library#random", as: :library_random
  get "/library/:series_slug", to: "series#show_from_library", as: :library_series
  get "/calendar", to: "calendar#index", as: :calendar
  get "/stats", to: "stats#show", as: :stats
  get "/history", to: "reading_history#index", as: :reading_history
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
  post "/sources/:source_slug/:series_slug/bulk_actions", to: "series#bulk_action", as: :source_series_bulk_actions
  post "/sources/:source_slug/:series_slug/refresh_metadata", to: "series#refresh_metadata", as: :source_series_refresh_metadata
  get "/chapters/:public_id", to: "chapters#redirect", as: :chapter_public
  get "/sources/:source_slug/:series_slug/chapters/:chapter_identifier",
      to: "chapters#show",
      as: :source_series_chapter,
      format: false,
      constraints: { chapter_identifier: /[^\/]+/ }
  patch "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/progress",
        to: "chapters#update_progress",
        as: :source_series_chapter_progress,
        format: false,
        constraints: { chapter_identifier: /[^\/]+/ }
  post "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/download",
       to: "chapters#enqueue_download",
       as: :source_series_chapter_download,
       format: false,
       constraints: { chapter_identifier: /[^\/]+/ }
  delete "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/download",
         to: "chapters#remove_download",
         as: :source_series_chapter_remove_download,
         format: false,
         constraints: { chapter_identifier: /[^\/]+/ }

  post "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/cancel_download",
       to: "chapters#cancel_download",
       as: :source_series_chapter_cancel_download,
       format: false,
       constraints: { chapter_identifier: /[^\/]+/ }

  namespace :admin do
    get "scrapers", to: "scrapers#index", as: :scrapers
    post "scrapers/:source_id/smoke", to: "scrapers#run_smoke", as: :scraper_smoke
    get "downloads", to: "downloads#index", as: :downloads
    post "downloads/refresh_all_covers", to: "downloads#refresh_all_covers", as: :refresh_all_covers
    post "downloads/refresh_all_metadata", to: "downloads#refresh_all_metadata", as: :refresh_all_metadata
    post "downloads/:id/restart", to: "downloads#restart", as: :download_restart
    post "downloads/:id/cancel", to: "downloads#cancel", as: :download_cancel
    post "downloads/restart_all_failed", to: "downloads#restart_all_failed", as: :restart_all_failed_downloads
    post "downloads/restart_all_stuck", to: "downloads#restart_all_stuck", as: :restart_all_stuck_downloads

    resources :users, only: %i[index new create destroy]

    # Backups
    get "backups", to: "backups#index", as: :backups
    post "backups", to: "backups#create", as: :create_backup
    get "backups/:id/download", to: "backups#download", as: :backup_download
    delete "backups/:id", to: "backups#destroy", as: :backup
    post "backups/:id/verify", to: "backups#verify", as: :backup_verify
  end

  # Settings
  get "/settings", to: "settings#show", as: :settings
  patch "/settings", to: "settings#update"
  patch "/settings/site", to: "settings#update_site_settings", as: :settings_site
  patch "/settings/source/:source_id", to: "settings#update_source", as: :settings_source
  patch "/settings/password", to: "settings#update_password", as: :settings_password
  post "/settings/regenerate_api_key", to: "settings#regenerate_api_key", as: :settings_regenerate_api_key
  patch "/settings/source_priority", to: "settings#update_source_priority", as: :settings_source_priority

  # Library Export/Import
  get "/export", to: "exports#show", as: :export
  post "/export", to: "exports#create"
  post "/import/preview", to: "exports#preview_library", as: :preview_library
  post "/import", to: "exports#import_library", as: :import_library
  post "/import/tachiyomi/preview", to: "exports#preview_tachiyomi", as: :preview_tachiyomi
  post "/import/tachiyomi", to: "exports#import_tachiyomi", as: :import_tachiyomi
  post "/export/tachiyomi", to: "exports#export_tachiyomi", as: :export_tachiyomi

  # Source Migrations
  resources :source_migrations, only: [ :index, :create ] do
    collection do
      post :preview
    end
  end

  # Mission Control for SolidQueue job monitoring
  mount MissionControl::Jobs::Engine, at: "/admin/jobs"

  # Error pages (used by config.exceptions_app = routes)
  match "/404", to: "errors#not_found", via: :all
  match "/422", to: "errors#unprocessable_entity", via: :all
  match "/500", to: "errors#internal_server_error", via: :all
end
