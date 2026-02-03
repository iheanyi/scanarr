class SearchController < ApplicationController
  def index
    @sources = Source.where(enabled: true).order(:name, :key)
    @query = params[:q].to_s.strip
    @selected_source_ids = params[:sources].present? ? Array(params[:sources]) : @sources.pluck(:id).map(&:to_s)

    @results = []
    return if @query.blank?

    selected_sources = @sources.where(id: @selected_source_ids)
    selected_sources.each do |source|
      begin
        adapter = adapter_for(source)
        adapter.search(@query).each do |result|
          @results << { source: source, result: result }
        end
      rescue => e
        Rails.logger.warn "Search failed for #{source.key}: #{e.message}"
      end
    end
  end

  private

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
  helper_method :source_slug
end
