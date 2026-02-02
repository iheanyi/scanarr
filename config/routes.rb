Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "sources#index"
  get "/sources/:source_slug/search", to: "sources#search", as: :source_search
  post "/sources/:source_slug/import", to: "sources#import", as: :source_import
  get "/sources/:source_slug", to: "series#index", as: :source_series_index
  get "/sources/:source_slug/:series_slug", to: "series#show", as: :source_series
  patch "/sources/:source_slug/:series_slug", to: "series#update", as: :source_series_update
  get "/chapters/:public_id", to: "chapters#redirect", as: :chapter_public
  get "/sources/:source_slug/:series_slug/chapters/:chapter_identifier", to: "chapters#show", as: :source_series_chapter
  post "/sources/:source_slug/:series_slug/chapters/:chapter_identifier/download",
       to: "chapters#enqueue_download",
       as: :source_series_chapter_download

  namespace :admin do
    get "scrapers", to: "scrapers#index", as: :scrapers
    post "scrapers/:source_id/smoke", to: "scrapers#run_smoke", as: :scraper_smoke
  end
end
