class SourcesController < ApplicationController
  before_action :set_source, only: %i[search browse preview import]

  helper_method :source_slug

  def index
    @sources = Source.where(enabled: true).order(:name)
  end

  BROWSE_PAGE_SIZE = 48

  def browse
    @sort = params[:sort].presence || "latest"
    @page = (params[:page].presence || 1).to_i
    @results = []
    @error = nil

    unless AdapterRegistry.registered?(@source.key)
      @error = "This source doesn't have an adapter yet"
      return
    end

    adapter = AdapterRegistry.for(@source)

    unless adapter.supports_browse?
      @error = "This source doesn't support browsing yet"
      return
    end

    @sort_options = adapter.browse_sort_options
    @results = adapter.browse(sort: @sort, page: @page, limit: BROWSE_PAGE_SIZE)
  rescue BaseAdapter::BrowseNotSupportedError => e
    @error = e.message
  rescue StandardError => e
    @error = "Browse failed: #{e.message}"
    Rails.logger.warn "Browse failed for #{@source.key}: #{e.class} - #{e.message}"
  end

  def preview
    @series_url = params[:series_url].to_s
    @series = nil
    @chapters = []
    @error = nil

    if @series_url.blank?
      @error = "No series URL provided"
      return
    end

    unless AdapterRegistry.registered?(@source.key)
      @error = "This source doesn't have an adapter yet"
      return
    end

    adapter = AdapterRegistry.for(@source)
    @series = adapter.series(@series_url)
    @chapters = adapter.chapters(@series_url).first(10) # Preview first 10 chapters
  rescue BaseAdapter::SeriesNotFoundError => e
    @error = "Series not found: #{e.message}"
  rescue StandardError => e
    @error = "Failed to load series: #{e.message}"
    Rails.logger.warn "Preview failed for #{@source.key}: #{e.class} - #{e.message}"
  end

  def search
    @query = params[:q].to_s.strip
    @results = []
    @error = nil

    return if @query.blank?

    unless AdapterRegistry.registered?(@source.key)
      @error = "This source doesn't have a search adapter yet"
      return
    end

    @results = AdapterRegistry.for(@source).search(@query)
  rescue StandardError => e
    @error = "Search failed: #{e.message}"
    Rails.logger.warn "Search failed for #{@source.key}: #{e.class} - #{e.message}"
  end

  def import
    series_url = params[:series_url].to_s
    if series_url.blank?
      redirect_to source_search_path(source_slug: source_slug(@source)), alert: "No series URL provided" and return
    end

    unless AdapterRegistry.registered?(@source.key)
      redirect_to search_path, alert: "Import not available for this source" and return
    end

    importer = SeriesImporter.new(source: @source, adapter: AdapterRegistry.for(@source))
    series = importer.import!(series_url)
    chapter_count = series.chapters.where(source: @source).count

    # Ensure library series exists for the follow button
    series.ensure_library_series!

    flash[:notice] = "Imported \"#{series.canonical_title}\" with #{chapter_count} #{'chapter'.pluralize(chapter_count)}. Follow this series to get notified of new chapters!"
    redirect_to source_series_path(
      source_slug: source_slug(@source),
      series_slug: series.to_param
    )
  rescue BaseAdapter::ScraperError, StandardError => e
    Rails.logger.error "Import failed for #{series_url}: #{e.class} - #{e.message}"
    redirect_to search_path(q: params[:q]), alert: "Import failed: #{e.message}"
  end

  private

  def set_source
    @source = Source.find_by!(slug: params[:source_slug])
  end

  def source_slug(source)
    source.slug
  end
end
