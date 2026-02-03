module Admin
  class DownloadsController < ApplicationController
    def index
      @statuses = %w[queued downloading complete failed]

      @downloads = FileAsset.includes(release: { chapter: :series })
                            .where.not(download_status: "pending")
                            .order(updated_at: :desc)

      @downloads = @downloads.where(download_status: params[:status]) if params[:status].present?
      @downloads = @downloads.page(params[:page]).per(25)

      # Stats for summary cards
      @stats = FileAsset.where.not(download_status: "pending")
                        .group(:download_status)
                        .count

      # Cover stats
      @series_count = Series.count
      @covers_attached = Series.joins(:cover_attachment).count
      @covers_with_url = Series.where.not(cover_url: [ nil, "" ]).count
    end

    def refresh_all_covers
      series_with_urls = Series.where.not(cover_url: [ nil, "" ])
      refreshed = 0

      series_with_urls.find_each do |series|
        series.cover.purge if series.cover.attached?
        download_cover(series, series.cover_url)
        refreshed += 1
      end

      flash[:notice] = "Refreshed #{refreshed} cover(s)"
      redirect_to admin_downloads_path
    end

    private

    def download_cover(series, cover_url)
      uri = URI.parse(cover_url)
      response = Net::HTTP.get_response(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      content_type = response["content-type"]
      extension = case content_type
      when /jpeg|jpg/i then "jpg"
      when /png/i then "png"
      when /webp/i then "webp"
      when /gif/i then "gif"
      else "jpg"
      end

      series.cover.attach(
        io: StringIO.new(response.body),
        filename: "cover.#{extension}",
        content_type: content_type
      )
    rescue StandardError => e
      Rails.logger.warn "Failed to download cover for #{series.canonical_title}: #{e.message}"
    end
  end
end
