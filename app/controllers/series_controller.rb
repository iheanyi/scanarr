class SeriesController < ApplicationController
  before_action :set_source, except: :show_from_library

  SORT_OPTIONS = {
    "alphabetical" => "A–Z",
    "reverse_alpha" => "Z–A",
    "most_chapters" => "Most Chapters",
    "recently_added" => "Recently Added"
  }.freeze

  def index
    @sort_by = params[:sort_by].presence || "alphabetical"
    @sort_options = SORT_OPTIONS

    scope = Series.joins(:series_sources)
                  .where(series_sources: { source_id: @source.id })
                  .includes(cover_attachment: :blob)

    @series = case @sort_by
    when "reverse_alpha"
                scope.order(canonical_title: :desc)
    when "most_chapters"
                scope.order(chapters_count: :desc, canonical_title: :asc)
    when "recently_added"
                scope.order(created_at: :desc)
    else # alphabetical
                scope.order(canonical_title: :asc)
    end
  end

  def show
    @series = find_series_by_param!
    redirect_to library_series_path(series_slug: @series.to_param), status: :moved_permanently
  end

  def show_from_library
    @series = Series.find_by_param!(params[:series_slug])
    @source = @series.primary_source || @series.sources.first
    raise ActiveRecord::RecordNotFound, "No source found for series" unless @source

    load_show_data
    render :show
  end

  def update
    @series = find_series_by_param!
    @series.update!(series_params)

    respond_to do |format|
      format.html { redirect_to library_series_path(series_slug: @series.to_param) }
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("toast-container",
          UI::ToastComponent.new(message: "Reading style updated", variant: :success))
      end
    end
  end

  def download_all
    @series = find_series_by_param!

    # Fan out downloads via background job
    DownloadAllJob.perform_later(@series.id, @source.id)

    respond_to do |format|
      format.html do
        flash[:notice] = "Queuing downloads in background..."
        redirect_to library_series_path(series_slug: @series.to_param)
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          "toast-container",
          UI::ToastComponent.new(message: "Queuing downloads in background...", variant: :success)
        )
      end
    end
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

    redirect_to library_series_path(series_slug: @series.to_param)
  end

  def remove_all_downloads
    @series = find_series_by_param!

    chapters = @series.chapters.where(source: @source)
                       .includes(releases: { file_asset: { pages: { image_attachment: :blob } } })
    removed = 0

    chapters.each do |chapter|
      chapter.releases.each do |release|
        file_asset = release.file_asset
        next unless file_asset

        # Purge all attached files (pages/images already preloaded)
        file_asset.archive.purge if file_asset.archive.attached?
        file_asset.pages.each { |page| page.image.purge if page.image.attached? }
        file_asset.pages.destroy_all
        file_asset.destroy!
        removed += 1
      end
    end

    flash[:notice] = "Removed #{removed} download(s)"
    redirect_to library_series_path(series_slug: @series.to_param)
  end

  def cancel_all_downloads
    @series = find_series_by_param!

    # Process cancellations in background with real-time updates
    CancelAllDownloadsJob.perform_later(@series.id, @source.id)

    flash[:notice] = "Cancelling downloads in background..."
    redirect_to library_series_path(series_slug: @series.to_param)
  end

  def bulk_action
    @series = find_series_by_param!
    chapter_ids = params[:chapter_ids].to_s.split(",").map(&:to_i)
    chapters = @series.chapters.where(id: chapter_ids, source: @source)

    case params[:action_name]
    when "download"
      series_source = @series.series_sources.find_by(source: @source)
      enqueued = 0
      chapters.includes(releases: :file_asset).each do |chapter|
        next if chapter.source_url.blank?
        latest = chapter.releases.to_a.max_by(&:created_at)
        next if latest&.file_asset&.download_status.in?(%w[queued pending downloading complete])

        release = chapter.releases.find_or_create_by!(source: @source)
        next if release.file_asset&.download_status.in?(%w[queued pending downloading complete])

        release.create_file_asset!(format: "pages", download_status: "queued", pages_downloaded: 0)
        DownloadChapterJob.perform_later(
          chapter.source_url,
          source_key: @source.key,
          series_title: @series.canonical_title,
          source_series_id: series_source&.source_series_id,
          chapter_number: chapter.chapter_number,
          chapter_title: chapter.title,
          language: chapter.language,
          group: chapter.group,
          release_id: release.id
        )
        enqueued += 1
      end
      flash[:notice] = "Queued #{enqueued} chapter(s) for download"

    when "remove"
      removed = 0
      chapters.includes(releases: { file_asset: { pages: { image_attachment: :blob } } }).each do |chapter|
        chapter.releases.each do |release|
          file_asset = release.file_asset
          next unless file_asset
          file_asset.archive.purge if file_asset.archive.attached?
          file_asset.pages.each { |page| page.image.purge if page.image.attached? }
          file_asset.pages.destroy_all
          file_asset.destroy!
          removed += 1
        end
      end
      flash[:notice] = "Removed #{removed} download(s)"

    when "mark_read"
      return unless current_user
      marked = 0
      chapters.each do |chapter|
        ChapterProgress.find_or_initialize_by(user: current_user, chapter: chapter).tap do |progress|
          progress.assign_attributes(status: "completed", page_index: 1, page_count: 1, progressed_at: Time.current)
          progress.save!
        end
        marked += 1
      end
      flash[:notice] = "Marked #{marked} chapter(s) as read"
    end

    redirect_to library_series_path(series_slug: @series.to_param)
  end

  def refresh_metadata
    @series = find_series_by_param!

    series_source = @series.series_sources.find_by(source: @source)
    unless series_source&.source_series_id.present?
      flash[:alert] = "No source URL available to refresh metadata"
      redirect_to library_series_path(series_slug: @series.to_param)
      return
    end

    # Re-import to update metadata including cover_url
    adapter = adapter_for(@source)
    importer = SeriesImporter.new(source: @source, adapter: adapter)
    importer.import!(series_source.source_series_id)

    flash[:notice] = "Metadata refreshed successfully"
    redirect_to library_series_path(series_slug: @series.to_param)
  rescue StandardError => e
    flash[:alert] = "Failed to refresh metadata: #{e.message}"
    redirect_to library_series_path(series_slug: @series.to_param)
  end

  private

  def load_show_data
    # Deduplicate chapters by (chapter_number_value, chapter_number), keeping newest per group.
    # DISTINCT ON requires matching leading ORDER BY, so we pick rows in a subquery
    # then re-sort for display.
    deduped_ids = @series.chapters
                         .where(source: @source)
                         .select("DISTINCT ON (chapter_number_value, chapter_number) id")
                         .order(
                           Arel.sql("chapter_number_value ASC NULLS LAST"),
                           :chapter_number,
                           Arel.sql("created_at DESC")
                         )
    @chapters = @series.chapters
                       .where(id: deduped_ids)
                       .includes(releases: :file_asset)
                       .order(
                         Arel.sql("chapter_number_value ASC NULLS LAST"),
                         Arel.sql("title ASC NULLS LAST"),
                         :chapter_number,
                         :id
                       )

    # Pre-compute latest release per chapter via SQL to avoid N+1
    # Uses the already-preloaded releases association for in-memory lookup
    @latest_release_map = {}
    @chapters.each do |chapter|
      @latest_release_map[chapter.id] = chapter.releases.to_a.max_by(&:created_at)
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

    build_reading_cta

    # Load error state for the current source
    @series_source = @series.series_sources.find_by(source: @source)
    @check_error = @series_source if @series_source&.check_failing?
  end

  def build_reading_cta
    @reading_cta_path = nil
    @reading_cta_label = nil
    return if @chapters.empty?

    started_reading = current_user && @chapter_progress_map.any?
    target_chapter = reading_target_chapter(started_reading: started_reading)
    return unless target_chapter

    @reading_cta_path = source_series_chapter_path(
      source_slug: @source.slug,
      series_slug: @series.to_param,
      chapter_identifier: chapter_identifier(target_chapter)
    )
    @reading_cta_label = started_reading ? "Continue reading" : "Start reading"
  end

  def reading_target_chapter(started_reading:)
    return @chapters.first unless started_reading

    in_progress = @chapter_progress_map.values
                                    .select { |progress| progress.status == "in_progress" }
                                    .max_by(&:progressed_at)
    return @chapter_progress_map.key(in_progress)&.then { |id| @chapters.find { |chapter| chapter.id == id } } if in_progress

    first_unread = @chapters.find { |chapter| @chapter_progress_map[chapter.id]&.status != "completed" }
    first_unread || @chapters.first
  end

  def series_params
    params.require(:series).permit(:reading_style)
  end

  def adapter_for(source)
    Scrapers::AdapterRegistry.for(source)
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
