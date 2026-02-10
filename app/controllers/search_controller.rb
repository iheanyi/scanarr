class SearchController < ApplicationController
  def index
    @sources = Source.where(enabled: true).order(:name, :key)
    @query = params[:q].to_s.strip
    @selected_source_ids = params[:sources].present? ? Array(params[:sources]) : @sources.pluck(:id).map(&:to_s)

    @results = []
    @errors = []
    return if @query.blank?

    selected_sources = @sources.where(id: @selected_source_ids)
    selected_sources.each do |source|
      search_source(source)
    end
  end

  private

  def search_source(source)
    unless Scrapers::AdapterRegistry.registered?(source.key)
      @errors << { source: source, message: "Adapter not implemented" }
      return
    end

    adapter = Scrapers::AdapterRegistry.for(source)
    adapter.search(@query).each do |result|
      @results << { source: source, result: result }
    end
  rescue Scrapers::AdapterRegistry::UnknownSourceError => e
    @errors << { source: source, message: "Source not configured" }
    Rails.logger.warn "Search skipped for #{source.key}: #{e.message}"
  rescue StandardError => e
    @errors << { source: source, message: e.message.truncate(100) }
    Rails.logger.warn "Search failed for #{source.key}: #{e.class} - #{e.message}"
  end

  def source_slug(source)
    source.slug
  end
  helper_method :source_slug
end
