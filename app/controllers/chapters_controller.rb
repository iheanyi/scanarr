class ChaptersController < ApplicationController
  before_action :load_context, only: %i[show enqueue_download update_progress remove_download cancel_download]
  # Authentication handled by ApplicationController

  helper_method :source_slug

  def show
    @release = latest_release
    file_asset = @release&.file_asset
    @pages = if file_asset&.download_status == "complete"
               pages = file_asset.pages.includes(image_attachment: :blob).order(:position).select { |page| page.image.attached? }

               # Verify blobs actually exist on disk (spot-check first page)
               if pages.any?
                 first_blob = pages.first.image.blob
                 if first_blob && !ActiveStorage::Blob.service.exist?(first_blob.key)
                   Rails.logger.warn "ChaptersController: Broken blobs detected for file_asset #{file_asset.id}, falling back to source"
                   []
                 else
                   pages
                 end
               else
                 []
               end
    else
               []
    end
    @file_asset = file_asset
    @download_in_progress = @file_asset&.download_status.in?(%w[queued pending downloading])
    @chapter_progress = current_user ? ChapterProgress.find_by(user: current_user, chapter: @chapter) : nil
    @reading_style = params[:reading_style].presence || @series.reading_style.presence || current_user&.effective_reading_style || "left_to_right"

    # Persist reading style preference to series if changed
    if params[:reading_style].present? && @series.reading_style != params[:reading_style]
      @series.update(reading_style: params[:reading_style])
    end
    @source_pages = []
    @source_error = nil
    if @pages.empty?
      source_url = @chapter.source_url || @release&.source_url
      if source_url.present?
        begin
          @source_pages = adapter_for(@source).pages(source_url)
        rescue BaseAdapter::ChapterNotFoundError => e
          @source_error = "This chapter is no longer available on the source. It may have been removed or replaced."
          Rails.logger.warn "Chapter not found: #{@chapter.id} - #{e.message}"
        rescue BaseAdapter::RateLimitError => e
          @source_error = "The source is rate limiting requests. Please try again in a few minutes."
          Rails.logger.warn "Rate limited: #{@chapter.id} - #{e.message}"
        rescue BaseAdapter::SourceUnavailableError, BaseAdapter::ScraperError => e
          @source_error = "Unable to load pages from source: #{e.message}"
          Rails.logger.error "Scraper error for chapter #{@chapter.id}: #{e.class} - #{e.message}"
        end
      end
    end
    set_initial_page_index
    set_navigation
  end

  def enqueue_download
    series_source = @series.series_sources.find_or_create_by!(source: @source)
    source_url = @chapter.source_url || latest_release&.source_url

    if source_url.blank?
      redirect_to source_series_chapter_path(
        source_slug: source_slug(@source),
        series_slug: @series.to_param,
        chapter_identifier: chapter_identifier(@chapter)
      ) and return
    end

    release = latest_release
    file_asset = release&.file_asset
    if file_asset&.download_status.in?(%w[queued pending downloading])
      redirect_to source_series_chapter_path(
        source_slug: source_slug(@source),
        series_slug: @series.to_param,
        chapter_identifier: chapter_identifier(@chapter)
      ) and return
    end

    ActiveRecord::Base.transaction do
      release = @chapter.releases.find_or_create_by!(source: @source) do |r|
        r.format = "pages"
        r.source_url = source_url
      end

      # Skip if this release already has an active download
      if release.file_asset&.download_status.in?(%w[queued pending downloading])
        redirect_to source_series_chapter_path(
          source_slug: source_slug(@source),
          series_slug: @series.to_param,
          chapter_identifier: chapter_identifier(@chapter)
        ) and return
      end

      chapter_path = LibraryPathBuilder.new(series: @series, source: @source).chapter_path(@chapter)
      file_asset = if release.file_asset
        release.file_asset.tap do |fa|
          fa.update!(download_status: "queued", pages_downloaded: 0, download_error: nil, path: chapter_path)
        end
      else
        release.create_file_asset!(
          format: "pages",
          download_status: "queued",
          pages_downloaded: 0,
          download_error: nil,
          path: chapter_path
        )
      end

      # Broadcast new download to admin page
      broadcast_admin_download(file_asset)

      DownloadChapterJob.perform_later(
        source_url,
        source_key: @source.key,
        series_title: @series.canonical_title,
        source_series_id: series_source&.source_series_id,
        chapter_number: @chapter.chapter_number,
        chapter_title: @chapter.title,
        language: @chapter.language,
        group: @chapter.group,
        release_id: release.id
      )
    end

    respond_to do |format|
      format.html do
        redirect_to source_series_chapter_path(
          source_slug: source_slug(@source),
          series_slug: @series.to_param,
          chapter_identifier: chapter_identifier(@chapter)
        )
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(@chapter),
          partial: "series/chapter_row",
          locals: chapter_row_locals
        )
      end
    end
  end

  def remove_download
    release = latest_release
    file_asset = release&.file_asset

    if file_asset
      # Purge all attached files (eager load to avoid N+1)
      file_asset.archive.purge if file_asset.archive.attached?
      file_asset.pages.includes(image_attachment: :blob).each do |page|
        page.image.purge if page.image.attached?
      end
      file_asset.pages.destroy_all
      file_asset.destroy!
      flash[:notice] = "Download removed for Chapter #{@chapter.chapter_number}"
    else
      flash[:alert] = "No download found to remove"
    end

    respond_to do |format|
      format.html do
        redirect_to source_series_path(
          source_slug: source_slug(@source),
          series_slug: @series.to_param
        )
      end
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            dom_id(@chapter),
            partial: "series/chapter_row",
            locals: chapter_row_locals
          ),
          turbo_stream.append(
            "toast-container",
            UI::ToastComponent.new(message: flash[:notice] || flash[:alert], variant: flash[:notice] ? :success : :danger)
          )
        ]
      end
    end
  end

  def cancel_download
    release = latest_release
    file_asset = release&.file_asset

    if file_asset&.download_status.in?(%w[queued pending downloading])
      # Purge any partially downloaded files (preload to avoid N+1)
      file_asset.archive.purge if file_asset.archive.attached?
      file_asset.pages.includes(image_attachment: :blob).each { |page| page.image.purge if page.image.attached? }
      file_asset.pages.destroy_all

      # Reset status to cancelled
      file_asset.update!(
        download_status: "cancelled",
        pages_downloaded: 0,
        pages_expected: nil,
        download_error: "Cancelled by user"
      )
      flash[:notice] = "Download cancelled for Chapter #{@chapter.chapter_number}"
    else
      flash[:alert] = "No active download to cancel"
    end

    respond_to do |format|
      format.html do
        redirect_to source_series_path(
          source_slug: source_slug(@source),
          series_slug: @series.to_param
        )
      end
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            dom_id(@chapter),
            partial: "series/chapter_row",
            locals: chapter_row_locals
          ),
          turbo_stream.append(
            "toast-container",
            UI::ToastComponent.new(message: flash[:notice] || flash[:alert], variant: flash[:notice] ? :success : :warning)
          )
        ]
      end
    end
  end

  def update_progress
    page_index = params[:page_index].to_i
    page_count = params[:page_count].to_i
    status = page_index >= page_count ? "completed" : "in_progress"

    progress = ChapterProgress.find_or_initialize_by(user: current_user, chapter: @chapter)
    progress.assign_attributes(
      page_index: page_index,
      page_count: page_count,
      status: status,
      progressed_at: Time.current
    )
    progress.save!

    render json: {
      status: progress.status,
      page_index: progress.page_index,
      page_count: progress.page_count
    }
  end

  def redirect
    chapter = Chapter.find_by!(public_id: params[:public_id])
    series = chapter.series
    source = chapter.source || chapter.releases.first&.source
    raise ActiveRecord::RecordNotFound, "Source not found" unless source

    identifier = chapter.chapter_number.presence || chapter.public_id
    redirect_to source_series_chapter_path(
      source_slug: source_slug(source),
      series_slug: series.to_param,
      chapter_identifier: identifier
    )
  end

  private

  def load_context
    @source = find_source
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .find_by_param!(params[:series_slug])

    identifier = params[:chapter_identifier].to_s
    chapter_scope = @series.chapters.where(source: @source)
    @chapter = chapter_scope.find_by(public_id: identifier) || chapter_scope.find_by(chapter_number: identifier)
    raise ActiveRecord::RecordNotFound, "Chapter not found" unless @chapter
  end

  def latest_release
    releases = @chapter.releases.where(source: @source)
                       .includes(file_asset: { pages: { image_attachment: :blob } })
                       .order(created_at: :desc)

    # Prefer the newest release whose downloaded files actually exist on disk
    releases.each do |release|
      fa = release.file_asset
      next unless fa&.download_status == "complete"

      first_page = fa.pages.min_by(&:position)
      next unless first_page&.image&.blob

      if ActiveStorage::Blob.service.exist?(first_page.image.blob.key)
        return release
      end
    end

    # Fall back to newest release (may have no download yet, or all are broken)
    releases.first
  end

  def set_navigation
    base = @series.chapters.where(source: @source)
    current_val = @chapter.chapter_number_value

    if current_val
      @previous_chapter = base
        .where("chapter_number_value < ?", current_val)
        .order(Arel.sql("chapter_number_value DESC"))
        .first

      @next_chapter = base
        .where("chapter_number_value > ?", current_val)
        .order(Arel.sql("chapter_number_value ASC"))
        .first
    else
      # Fallback for chapters without a numeric value
      @previous_chapter = base.where("id < ?", @chapter.id).order(id: :desc).first
      @next_chapter = base.where("id > ?", @chapter.id).order(id: :asc).first
    end
  end

  def set_initial_page_index
    page_count = @pages.any? ? @pages.length : @source_pages.length
    page_param = params[:page].present? ? params[:page].to_i : nil

    if page_param && page_param > 0
      @initial_page_index = page_param
    elsif @chapter_progress&.page_index
      @initial_page_index = @chapter_progress.page_index
    else
      @initial_page_index = page_count.positive? ? 1 : 0
    end

    if page_count.positive?
      @initial_page_index = [ [ @initial_page_index, page_count ].min, 1 ].max
    else
      @initial_page_index = 0
    end
  end

  def find_source
    Source.find_by!(slug: params[:source_slug])
  end

  def adapter_for(source)
    AdapterRegistry.for(source)
  end

  def source_slug(source)
    source.slug
  end

  def chapter_row_locals
    @chapter.reload
    latest_release = @chapter.releases.includes(:file_asset).order(created_at: :desc).first
    {
      chapter: @chapter,
      source: @source,
      series: @series,
      progress: current_user ? ChapterProgress.find_by(user: current_user, chapter: @chapter) : nil,
      latest_release: latest_release
    }
  end

  def broadcast_admin_download(file_asset)
    Turbo::StreamsChannel.broadcast_prepend_to(
      "admin_downloads",
      target: "downloads_list",
      partial: "admin/downloads/download_row",
      locals: { download: file_asset }
    )
  rescue StandardError => e
    Rails.logger.warn "ChaptersController: Failed to broadcast admin download: #{e.message}"
  end
end
