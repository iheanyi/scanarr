# frozen_string_literal: true

class SourceMigrationsController < ApplicationController
  def index
    @sources = Source.all.order(:name)
    @source_health = SeriesSource.group(:source_id).select(
      "source_id",
      "COUNT(*) as total_series",
      "SUM(CASE WHEN consecutive_failures >= 10 THEN 1 ELSE 0 END) as stale_count",
      "SUM(CASE WHEN consecutive_failures >= 3 AND consecutive_failures < 10 THEN 1 ELSE 0 END) as attention_count",
      "SUM(CASE WHEN consecutive_failures = 0 THEN 1 ELSE 0 END) as healthy_count"
    ).index_by(&:source_id)
  end

  def preview
    from_source = Source.find(params[:from_source_id])
    to_source = Source.find(params[:to_source_id])

    result = SourceMigrationService.new(
      from_source: from_source,
      to_source: to_source,
      user: current_user,
      series_ids: selected_series_ids
    ).preview

    unless result.success
      respond_with_toast(
        redirect_path: source_migrations_path,
        message: result.errors.first,
        variant: :danger,
        turbo_redirect: true
      )
      return
    end

    @from_source = from_source
    @to_source = to_source
    @result = result
    @series_chapter_counts = build_chapter_count_map(result)

    render :preview, status: :unprocessable_entity
  end

  def create
    from_source = Source.find(params[:from_source_id])
    to_source = Source.find(params[:to_source_id])

    result = SourceMigrationService.new(
      from_source: from_source,
      to_source: to_source,
      user: current_user,
      series_ids: selected_series_ids
    ).execute!

    if result.success
      message = "Migration complete! #{result.migrated.size} series migrated, " \
                "#{result.already_on_target.size} already on target, " \
                "#{result.no_match.size} could not be matched."
      variant = :success
    else
      message = "Migration had errors: #{result.errors.first(3).join('; ')}"
      variant = :danger
    end

    respond_with_toast(
      redirect_path: source_migrations_path,
      message: message,
      variant: variant,
      turbo_redirect: true
    )
  end

  def series_preview
    @series = Series.find_by_param!(params[:series_slug])
    @from_source = Source.find_by(id: params[:from_source_id]) || @series.primary_source || @series.sources.first
    if @from_source.blank?
      respond_with_toast(
        redirect_path: library_series_path(series_slug: @series.to_param),
        message: "No source available for this series",
        variant: :warning,
        turbo_redirect: true
      )
      return
    end

    @current_chapter_count = @series.chapters.where(source: @from_source).count

    discovery = SourceMigrationDiscoveryService.new(series: @series, from_source: @from_source).call
    @candidates = discovery.candidates
    @discovery_errors = discovery.errors
  end

  def series_create
    @series = Series.find_by_param!(params[:series_slug])
    @from_source = Source.find(params[:from_source_id])
    @to_source = Source.find(params[:to_source_id])

    # Validate the target before link_series_to_target! so a rejected
    # migration cannot leave behind a fresh SeriesSource link
    if (reason = @to_source.migration_target_rejection)
      respond_with_toast(
        redirect_path: library_series_path(series_slug: @series.to_param),
        message: "#{@to_source.name} is #{reason} and cannot be a migration target",
        variant: :danger,
        status: :unprocessable_entity,
        turbo_redirect: true
      )
      return
    end

    unless @series.sources.exists?(id: @to_source.id)
      target_series_url = params[:target_series_url].to_s
      if target_series_url.blank?
        respond_with_toast(
          redirect_path: library_series_migration_path(series_slug: @series.to_param, from_source_id: @from_source.id),
          message: "Series is not linked to #{@to_source.name} yet. Please choose a source candidate first.",
          variant: :warning,
          turbo_redirect: true
        )
        return
      end

      link_series_to_target!(target_series_url)
    end

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: current_user,
      series_ids: [ @series.id ]
    ).execute!

    if result.success && result.migrated.any?
      message = "Migrated #{@series.canonical_title} to #{@to_source.name}"
      variant = :success
    elsif result.success
      message = "#{@series.canonical_title} was already using #{@to_source.name}"
      variant = :info
    else
      message = "Migration had errors: #{result.errors.first(3).join('; ')}"
      variant = :danger
    end

    respond_with_toast(
      redirect_path: library_series_path(series_slug: @series.to_param),
      message: message,
      variant: variant,
      turbo_redirect: true
    )
  rescue Scrapers::AdapterRegistry::UnknownSourceError, Scrapers::Errors::ScraperError, ActiveRecord::RecordInvalid, ArgumentError => e
    respond_with_toast(
      redirect_path: library_series_migration_path(series_slug: @series.to_param, from_source_id: @from_source.id),
      message: "Failed to link/migrate #{@series.canonical_title}: #{e.message}",
      variant: :danger,
      status: :unprocessable_entity,
      turbo_redirect: true
    )
  end

  private

  def selected_series_ids
    return nil unless params.key?(:series_ids)

    Array(params[:series_ids])
  end

  def link_series_to_target!(target_series_url)
    unless Scrapers::AdapterRegistry.registered?(@to_source.key)
      raise Scrapers::AdapterRegistry::UnknownSourceError, "Adapter not implemented"
    end

    adapter = Scrapers::AdapterRegistry.for(@to_source)
    target_series = adapter.series(target_series_url)
    source_series_id = target_series.id.to_s.strip
    raise ArgumentError, "Could not resolve source identifier for #{@to_source.name}" if source_series_id.blank?

    series_source = @series.series_sources.find_or_initialize_by(source: @to_source)
    series_source.source_series_id = source_series_id
    series_source.save!
  end

  def build_chapter_count_map(result)
    series_ids = (result.already_on_target + result.link_candidates + result.no_match).map(&:id).uniq
    return {} if series_ids.empty?

    source_ids = [ @from_source.id, @to_source.id ]
    Chapter.where(series_id: series_ids, source_id: source_ids)
           .group(:series_id, :source_id)
           .count
  end
end
