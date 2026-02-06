class SeriesController < ApplicationController
  before_action :set_source

  def index
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .includes(:cover_attachment)
                    .order(:canonical_title)
  end

  def show
    @series = find_series_by_param!
    @chapters = @series.chapters
                       .where(source: @source)
                       .includes(releases: :file_asset)
                       .order(
                         Arel.sql("chapter_number_value ASC NULLS LAST"),
                         Arel.sql("title ASC NULLS LAST"),
                         :chapter_number,
                         :id
                       )

    # Pre-compute latest release and stats to avoid N+1 in views
    @latest_release_map = {}
    @chapters.each do |chapter|
      @latest_release_map[chapter.id] = chapter.releases.max_by(&:created_at)
    end

    # Pre-compute chapter stats
    @downloadable_count = 0
    @downloaded_count = 0
    @in_progress_count = 0
    @chapters.each do |chapter|
      release = @latest_release_map[chapter.id]
      status = release&.file_asset&.download_status
      if status == "complete"
        @downloaded_count += 1
      elsif status.in?(%w[queued pending downloading])
        @in_progress_count += 1
      elsif chapter.source_url.present?
        @downloadable_count += 1
      end
    end

    if current_user
      @chapter_progress_map = ChapterProgress.where(user: current_user, chapter_id: @chapters.map(&:id))
                                              .index_by(&:chapter_id)

      # Ensure library series exists so the follow button is always available
      @series.ensure_library_series! if @series.library_series.blank?

      # Load follow data for current user
      if @series.library_series
        @user_follow = current_user.user_series_follows.find_by(library_series: @series.library_series)
      end
    else
      @chapter_progress_map = {}
    end
  end

  def update
    @series = find_series_by_param!
    @series.update!(series_params)

    respond_to do |format|
      format.html { redirect_to source_series_path(source_slug: @source.slug, series_slug: @series.to_param) }
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("toast-container",
          partial: "shared/toast",
          locals: { message: "Reading style updated", variant: :success })
      end
    end
  end

  def download_all
    @series = find_series_by_param!

    # Fan out downloads via background job
    DownloadAllJob.perform_later(@series.id, @source.id)

    flash[:notice] = "Queuing downloads in background..."
    redirect_to source_series_path(source_slug: @source.slug, series_slug: @series.to_param)
  end

  def refresh_cover
    @series = find_series_by_param!

    if @series.cover_url.present?
      # Force re-download by purging existing cover
      @series.cover.purge if @series.cover.attached?
      CoverDownloader.download(@series, @series.cover_url)
      flash[:notice] = "Cover image refreshed"
    else
      flash[:alert] = "No cover URL available to refresh"
    end

    redirect_to source_series_path(source_slug: @source.slug, series_slug: @series.to_param)
  end

  def remove_all_downloads
    @series = find_series_by_param!

    chapters = @series.chapters.where(source: @source).includes(releases: :file_asset)
    removed = 0

    chapters.each do |chapter|
      chapter.releases.each do |release|
        file_asset = release.file_asset
        next unless file_asset

        # Purge all attached files
        file_asset.archive.purge if file_asset.archive.attached?
        file_asset.pages.each { |page| page.image.purge if page.image.attached? }
        file_asset.pages.destroy_all
        file_asset.destroy!
        removed += 1
      end
    end

    flash[:notice] = "Removed #{removed} download(s)"
    redirect_to source_series_path(source_slug: @source.slug, series_slug: @series.to_param)
  end

  def cancel_all_downloads
    @series = find_series_by_param!

    # Process cancellations in background with real-time updates
    CancelAllDownloadsJob.perform_later(@series.id, @source.id)

    flash[:notice] = "Cancelling downloads in background..."
    redirect_to source_series_path(source_slug: @source.slug, series_slug: @series.to_param)
  end

  def refresh_metadata
    @series = find_series_by_param!

    series_source = @series.series_sources.find_by(source: @source)
    unless series_source&.source_series_id.present?
      flash[:alert] = "No source URL available to refresh metadata"
      redirect_to source_series_path(source_slug: @source.slug, series_slug: @series.to_param)
      return
    end

    # Re-import to update metadata including cover_url
    adapter = adapter_for(@source)
    importer = SeriesImporter.new(source: @source, adapter: adapter)
    importer.import!(series_source.source_series_id)

    flash[:notice] = "Metadata refreshed successfully"
    redirect_to source_series_path(source_slug: @source.slug, series_slug: @series.to_param)
  rescue StandardError => e
    flash[:alert] = "Failed to refresh metadata: #{e.message}"
    redirect_to source_series_path(source_slug: @source.slug, series_slug: @series.to_param)
  end

  private

  def series_params
    params.require(:series).permit(:reading_style)
  end

  def adapter_for(source)
    AdapterRegistry.for(source)
  end

  def set_source
    @source = Source.find_by!(slug: params[:source_slug])
  end

  def find_series_by_param!
    Series.joins(:series_sources)
          .where(series_sources: { source_id: @source.id })
          .find_by_param!(params[:series_slug])
  end
end
