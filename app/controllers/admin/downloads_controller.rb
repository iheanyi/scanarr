module Admin
  class DownloadsController < ApplicationController
    def index
      @statuses = %w[queued downloading complete failed]

      @downloads = FileAsset.includes(release: { chapter: :series })
                            .where.not(download_status: %w[pending cancelled])
                            .order(updated_at: :desc)

      # Allow filtering by specific status, including cancelled if explicitly requested
      if params[:status].present?
        @downloads = FileAsset.includes(release: { chapter: :series })
                              .where(download_status: params[:status])
                              .order(updated_at: :desc)
      end

      @downloads = @downloads.page(params[:page]).per(25)

      # Stats for summary cards (exclude pending and cancelled from main stats)
      @stats = FileAsset.where.not(download_status: %w[pending cancelled])
                        .group(:download_status)
                        .count

      # Cancelled count shown separately
      @cancelled_count = FileAsset.where(download_status: "cancelled").count

      # Cover stats - show all series, not just ones with cover_url
      @series_count = Series.count
      @covers_attached = Series.joins(:cover_attachment).count
      @covers_missing = @series_count - @covers_attached
    end

    def refresh_all_covers
      # Process ALL series covers in background (fetches from source if needed)
      RefreshAllCoversJob.perform_later

      flash[:notice] = "Refreshing all covers in background..."
      redirect_to admin_downloads_path
    end
  end
end
