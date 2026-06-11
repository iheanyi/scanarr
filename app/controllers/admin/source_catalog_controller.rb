module Admin
  class SourceCatalogController < AdminController
    PER_PAGE = 50

    def index
      @implemented_ids = Scrapers::Manifest.entries.filter_map(&:mihon_id).to_set
      @total_count = UpstreamSource.count
      @implemented_count = UpstreamSource.where(mihon_id: @implemented_ids.to_a).count
      @last_refreshed_at = UpstreamSource.maximum(:last_seen_at)

      scope = UpstreamSource.order(:name)
      scope = scope.english unless params[:lang] == "all"
      if params[:q].present?
        scope = scope.where("name ILIKE ?", "%#{UpstreamSource.sanitize_sql_like(params[:q])}%")
      end
      @upstream_sources = scope.page(params[:page]).per(PER_PAGE)
    end

    def refresh
      RefreshUpstreamCatalogJob.perform_later
      respond_with_toast(
        redirect_path: admin_source_catalog_path,
        message: "Catalog refresh started",
        variant: :info
      )
    end
  end
end
