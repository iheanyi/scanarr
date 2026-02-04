module Admin
  class ScrapersController < ApplicationController
    def index
      @sources = Source.order(:name)
      @statuses = ScraperRun::STATUSES
      @run_types = ScraperRun.distinct.order(:run_type).pluck(:run_type)

      @runs = ScraperRun.includes(:source).order(created_at: :desc)
      @runs = @runs.where(source_id: params[:source_id]) if params[:source_id].present?
      @runs = @runs.where(status: params[:status]) if params[:status].present?
      @runs = @runs.where(run_type: params[:run_type]) if params[:run_type].present?
      @runs = @runs.limit(50)
    end

    def run_smoke
      source = Source.find(params[:source_id])
      run = ScraperRun.create!(
        source: source,
        run_type: "smoke",
        status: "running",
        started_at: Time.current
      )

      stats = run_smoke_for(source)
      run.update!(
        status: "success",
        finished_at: Time.current,
        stats_json: stats
      )
    rescue StandardError => error
      run&.update!(
        status: "failed",
        finished_at: Time.current,
        error: "#{error.class}: #{error.message}"
      )
    ensure
      redirect_to admin_scrapers_path
    end

    private

    def run_smoke_for(source)
      adapter = adapter_for(source)
      results = adapter.search("one piece")
      series = results.first && adapter.series(results.first.url)
      chapters = series ? adapter.chapters(series.url) : []
      pages = chapters.first ? adapter.pages(chapters.first.url) : []

      {
        query: "one piece",
        search_count: results.size,
        series_url: series&.url,
        chapter_count: chapters.size,
        page_count: pages.size
      }
    end

    def adapter_for(source)
      AdapterRegistry.for(source)
    end
  end
end
