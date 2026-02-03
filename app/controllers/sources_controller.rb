class SourcesController < ApplicationController
  before_action :set_source, only: %i[search import]

  helper_method :source_slug

  def index
    @sources = Source.where(enabled: true).order(:key)
  end

  def search
    @query = params[:q].to_s.strip
    @results = @query.present? ? adapter_for(@source).search(@query) : []
  end

  def import
    series_url = params[:series_url].to_s
    if series_url.blank?
      redirect_to source_search_path(source_slug: source_slug(@source)), alert: "No series URL provided" and return
    end

    importer = SeriesImporter.new(source: @source, adapter: adapter_for(@source))
    series = importer.import!(series_url)
    chapter_count = series.chapters.where(source: @source).count

    flash[:notice] = "Imported \"#{series.canonical_title}\" with #{chapter_count} #{'chapter'.pluralize(chapter_count)}"
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
    key = params[:source_slug].to_s.tr("-", "_")
    @source = Source.find_by!(key: key)
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

  def source_slug(source)
    source.key.to_s.tr("_", "-")
  end
end
