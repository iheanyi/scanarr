module Admin
  class DownloadsController < ApplicationController
    include DownloadBroadcasting

    before_action :require_admin
    before_action :set_download, only: %i[restart cancel]

    # Custom ordering:
    #   1) downloading (sorted by progress)
    #   2) queued
    #   3) complete
    #   4) everything else
    STATUS_ORDER = Arel.sql(<<~SQL.squish)
      CASE download_status
        WHEN 'downloading' THEN 1
        WHEN 'queued' THEN 2
        WHEN 'complete' THEN 3
        ELSE 4
      END
    SQL

    DOWNLOAD_PROGRESS_ORDER = Arel.sql(<<~SQL.squish)
      CASE
        WHEN download_status = 'downloading'
          THEN COALESCE(CAST(pages_downloaded AS FLOAT) / NULLIF(pages_expected, 0), 0)
        ELSE NULL
      END DESC
    SQL

    def index
      @statuses = %w[queued pending downloading complete failed]

      @downloads = FileAsset.includes(release: { chapter: :series })
                            .where.not(download_status: %w[pending cancelled])
                            .order(STATUS_ORDER, DOWNLOAD_PROGRESS_ORDER, updated_at: :desc)

      # Allow filtering by specific status, including cancelled if explicitly requested
      if params[:status].present?
        @downloads = FileAsset.includes(release: { chapter: :series })
                              .where(download_status: params[:status])
                              .order(STATUS_ORDER, DOWNLOAD_PROGRESS_ORDER, updated_at: :desc)
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

      respond_with_toast(
        redirect_path: admin_downloads_path,
        message: "Refreshing all covers in background...",
        variant: :success
      )
    end

    def refresh_all_metadata
      RefreshAllMetadataJob.perform_later

      respond_with_toast(
        redirect_path: admin_downloads_path,
        message: "Refreshing all metadata in background...",
        variant: :success
      )
    end

    def restart
      if @download.download_status.in?(%w[failed cancelled])
        @download.update!(
          download_status: "queued",
          download_error: nil,
          pages_downloaded: 0
        )
        broadcast_live_updates(@download)

        enqueue_download_job(@download)

        message = "Download restarted successfully"
        variant = :success
      else
        message = "Can only restart failed or cancelled downloads"
        variant = :warning
      end

      respond_with_toast(
        redirect_path: admin_downloads_path(status: params[:status]),
        message: message,
        variant: variant
      )
    end

    def cancel
      if @download.download_status.in?(%w[queued pending downloading])
        @download.archive.purge if @download.archive.attached?
        @download.pages.includes(image_attachment: :blob).each { |page| page.image.purge if page.image.attached? }
        @download.pages.destroy_all
        @download.update!(
          download_status: "cancelled",
          pages_downloaded: 0,
          pages_expected: nil,
          download_error: "Cancelled by user"
        )
        broadcast_live_updates(@download)
        message = "Download cancelled"
        variant = :success
      else
        message = "Can only cancel queued or in-progress downloads"
        variant = :warning
      end

      respond_with_toast(
        redirect_path: admin_downloads_path(status: params[:status]),
        message: message,
        variant: variant
      )
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
          broadcast_live_updates(download)
          enqueue_download_job(download)
        end

        message = "Restarted #{count} failed download#{'s' if count != 1}"
        variant = :success
      else
        message = "No failed downloads to restart"
        variant = :warning
      end

      respond_with_toast(
        redirect_path: admin_downloads_path,
        message: message,
        variant: variant
      )
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
          broadcast_live_updates(download)
          enqueue_download_job(download)
        end

        message = "Restarted #{count} stuck download#{'s' if count != 1}"
        variant = :success
      else
        message = "No stuck downloads to restart"
        variant = :warning
      end

      respond_with_toast(
        redirect_path: admin_downloads_path,
        message: message,
        variant: variant
      )
    end

    private

    def set_download
      @download = FileAsset.find_by(public_id: params[:id]) || FileAsset.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      respond_with_toast(
        redirect_path: admin_downloads_path(status: params[:status]),
        message: "Download not found",
        variant: :danger,
        status: :not_found,
        turbo_redirect: true
      )
      nil
    end

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

    def broadcast_live_updates(file_asset)
      broadcast_admin_download_update(file_asset)
      broadcast_chapter_update(file_asset)
    end

    def broadcast_chapter_update(file_asset)
      release = file_asset.release
      chapter = release&.chapter
      series = chapter&.series
      source = release&.source || chapter&.source

      broadcast_chapter_row_update(
        chapter: chapter,
        series: series,
        source: source,
        log_prefix: self.class.name
      )
    end
  end
end
