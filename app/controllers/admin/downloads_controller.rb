module Admin
  class DownloadsController < ApplicationController
    # Custom ordering: downloading first, then queued, then complete, then failed
    STATUS_ORDER = Arel.sql(<<~SQL.squish)
      CASE download_status
        WHEN 'downloading' THEN 1
        WHEN 'queued' THEN 2
        WHEN 'pending' THEN 3
        WHEN 'complete' THEN 4
        WHEN 'failed' THEN 5
        ELSE 6
      END
    SQL

    def index
      @statuses = %w[queued downloading complete failed]

      @downloads = FileAsset.includes(release: { chapter: :series })
                            .where.not(download_status: %w[pending cancelled])
                            .order(STATUS_ORDER, updated_at: :desc)

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

      # Stuck count (downloading for 10+ minutes)
      @stuck_count = FileAsset.where(download_status: "downloading")
                              .where("updated_at < ?", 10.minutes.ago)
                              .count

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

    def refresh_all_metadata
      RefreshAllMetadataJob.perform_later

      flash[:notice] = "Refreshing all metadata in background..."
      redirect_to admin_downloads_path
    end

    def restart
      @download = FileAsset.find(params[:id])

      if @download.download_status.in?(%w[failed downloading cancelled])
        @download.update!(
          download_status: "queued",
          download_error: nil,
          pages_downloaded: 0
        )

        enqueue_download_job(@download)

        flash[:notice] = "Download restarted successfully"
      else
        flash[:alert] = "Can only restart failed, stuck, or cancelled downloads"
      end

      redirect_to admin_downloads_path(status: params[:status])
    end

    def cancel
      @download = FileAsset.find(params[:id])

      if @download.download_status.in?(%w[queued pending downloading])
        @download.archive.purge if @download.archive.attached?
        @download.pages.each { |page| page.image.purge if page.image.attached? }
        @download.pages.destroy_all
        @download.update!(
          download_status: "cancelled",
          pages_downloaded: 0,
          pages_expected: nil,
          download_error: "Cancelled by user"
        )
        flash[:notice] = "Download cancelled"
      else
        flash[:alert] = "Can only cancel queued or in-progress downloads"
      end

      redirect_to admin_downloads_path(status: params[:status])
    end

    def restart_all_failed
      failed_downloads = FileAsset.where(download_status: "failed").includes(release: { chapter: :series })
      count = failed_downloads.count

      if count > 0
        failed_downloads.find_each do |download|
          download.update!(
            download_status: "queued",
            download_error: nil,
            pages_downloaded: 0
          )
          enqueue_download_job(download)
        end

        flash[:notice] = "Restarted #{count} failed download#{'s' if count != 1}"
      else
        flash[:alert] = "No failed downloads to restart"
      end

      redirect_to admin_downloads_path
    end

    def restart_all_stuck
      # Stuck = downloading for more than 10 minutes with no progress
      stuck_downloads = FileAsset.where(download_status: "downloading")
                                 .where("updated_at < ?", 10.minutes.ago)
                                 .includes(release: { chapter: :series })
      count = stuck_downloads.count

      if count > 0
        stuck_downloads.find_each do |download|
          download.update!(
            download_status: "queued",
            download_error: nil,
            pages_downloaded: 0
          )
          enqueue_download_job(download)
        end

        flash[:notice] = "Restarted #{count} stuck download#{'s' if count != 1}"
      else
        flash[:alert] = "No stuck downloads to restart"
      end

      redirect_to admin_downloads_path
    end

    private

    def enqueue_download_job(file_asset)
      release = file_asset.release
      chapter = release&.chapter
      series = chapter&.series
      source = release&.source || chapter&.source

      return unless chapter && series && source && chapter.source_url.present?

      series_source = series.series_sources.find_by(source: source)

      DownloadChapterJob.perform_later(
        chapter.source_url,
        source_key: source.key,
        series_title: series.canonical_title,
        source_series_id: series_source&.source_series_id,
        chapter_number: chapter.chapter_number,
        chapter_title: chapter.title,
        language: chapter.language,
        group: chapter.group,
        release_id: release.id
      )
    end
  end
end
