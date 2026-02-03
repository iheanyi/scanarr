class SeriesController < ApplicationController
  before_action :set_source

  def index
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .order(:canonical_title)
  end

  def show
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .friendly
                    .find(params[:series_slug])
    @chapters = @series.chapters
                       .where(source: @source)
                       .includes(releases: :file_asset)
                       .order(
                         Arel.sql("chapter_number_value ASC NULLS LAST"),
                         Arel.sql("title ASC NULLS LAST"),
                         :chapter_number,
                         :id
                       )
    if current_user
      @chapter_progress_map = ChapterProgress.where(user: current_user, chapter_id: @chapters.map(&:id))
                                              .index_by(&:chapter_id)
    else
      @chapter_progress_map = {}
    end
  end

  def update
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .friendly
                    .find(params[:series_slug])
    @series.update!(series_params)
    redirect_to source_series_path(source_slug: @source.key.to_s.tr("_", "-"), series_slug: @series.friendly_id)
  end

  def download_all
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .friendly
                    .find(params[:series_slug])

    # Fan out downloads via background job
    DownloadAllJob.perform_later(@series.id, @source.id)

    flash[:notice] = "Queuing downloads in background..."
    redirect_to source_series_path(source_slug: @source.key.to_s.tr("_", "-"), series_slug: @series.friendly_id)
  end

  def refresh_cover
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .friendly
                    .find(params[:series_slug])

    if @series.cover_url.present?
      # Force re-download by purging existing cover
      @series.cover.purge if @series.cover.attached?
      download_cover(@series, @series.cover_url)
      flash[:notice] = "Cover image refreshed"
    else
      flash[:alert] = "No cover URL available to refresh"
    end

    redirect_to source_series_path(source_slug: @source.key.to_s.tr("_", "-"), series_slug: @series.friendly_id)
  end

  def remove_all_downloads
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .friendly
                    .find(params[:series_slug])

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
    redirect_to source_series_path(source_slug: @source.key.to_s.tr("_", "-"), series_slug: @series.friendly_id)
  end

  def refresh_metadata
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .friendly
                    .find(params[:series_slug])

    series_source = @series.series_sources.find_by(source: @source)
    unless series_source&.source_series_id.present?
      flash[:alert] = "No source URL available to refresh metadata"
      redirect_to source_series_path(source_slug: @source.key.to_s.tr("_", "-"), series_slug: @series.friendly_id)
      return
    end

    # Re-import to update metadata including cover_url
    adapter = adapter_for(@source)
    importer = SeriesImporter.new(source: @source, adapter: adapter)
    importer.import!(series_source.source_series_id)

    flash[:notice] = "Metadata refreshed successfully"
    redirect_to source_series_path(source_slug: @source.key.to_s.tr("_", "-"), series_slug: @series.friendly_id)
  rescue StandardError => e
    flash[:alert] = "Failed to refresh metadata: #{e.message}"
    redirect_to source_series_path(source_slug: @source.key.to_s.tr("_", "-"), series_slug: @series.friendly_id)
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

  def series_params
    params.require(:series).permit(:reading_style)
  end

  def adapter_for(source)
    case source.key.to_s
    when "weeb_central"
      WeebCentral::Adapter.new(config: Rails.configuration.scraper_sources.fetch("weeb_central", {}))
    when "mangadex"
      Mangadex::Adapter.new(config: Rails.configuration.scraper_sources.fetch("mangadex", {}))
    else
      raise ArgumentError, "Unknown source key #{source.key.inspect}"
    end
  end

  def set_source
    key = params[:source_slug].to_s.tr("-", "_")
    @source = Source.find_by!(key: key)
  end
end
