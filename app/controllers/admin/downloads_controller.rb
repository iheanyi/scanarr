module Admin
  class DownloadsController < ApplicationController
    def index
      @statuses = %w[queued downloading complete failed]

      @downloads = FileAsset.includes(release: { chapter: :series })
                            .where.not(download_status: "pending")
                            .order(updated_at: :desc)

      @downloads = @downloads.where(download_status: params[:status]) if params[:status].present?
      @downloads = @downloads.limit(100)

      # Stats for summary cards
      @stats = FileAsset.where.not(download_status: "pending")
                        .group(:download_status)
                        .count
    end
  end
end
