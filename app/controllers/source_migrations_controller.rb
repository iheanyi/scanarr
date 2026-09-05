# frozen_string_literal: true

class SourceMigrationsController < ApplicationController
  def index
    @sources = Source.all.order(:name)
    @target_sources = @sources.select { |source| source.migration_target_rejection.nil? && Scrapers::AdapterRegistry.registered?(source.key) }
    @source_health = SeriesSource.where(series_id: followed_series.select(:id)).group(:source_id).select(
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
      series_ids: selected_series_ids,
      auto_link: false
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

    render :preview, formats: [ :html ]
  end

  def create
    from_source = Source.find(params[:from_source_id])
    to_source = Source.find(params[:to_source_id])

    result = SourceMigrationService.new(
      from_source: from_source,
      to_source: to_source,
      user: current_user,
      series_ids: selected_series_ids,
      auto_link: false
    ).execute!

    queue_replacement_checks(result, to_source)

    @from_source = from_source
    @to_source = to_source
    @result = result
    render :complete, formats: [ :html ]
  end

  def series_preview
    @series = Series.find_by_param!(params[:series_slug])
    unless followed_series.exists?(id: @series.id)
      redirect_to library_series_path(series_slug: @series.to_param), alert: "Follow this series before choosing a replacement source."
      return
    end
    @from_source = @series.sources.find_by(id: params[:from_source_id]) || preferred_source(@series)
    if @from_source.blank?
      respond_with_toast(
        redirect_path: library_series_path(series_slug: @series.to_param),
        message: "No source available for this series",
        variant: :warning,
        turbo_redirect: true
      )
      return
    end

    @target_sources = Source.order(:name).where.not(id: @from_source.id).select do |source|
      source.migration_target_rejection.nil? && Scrapers::AdapterRegistry.registered?(source.key)
    end
    @candidates = []
    @discovery_errors = []
    if params[:matches_only] == "1"
      if @target_sources.any? { |source| source.id.to_s == params[:to_source_id].to_s }
        discovery = SourceMigrationDiscoveryService.new(series: @series, from_source: @from_source, source_id: params[:to_source_id]).call
        @candidates = discovery.candidates
        @discovery_errors = discovery.errors
      else
        @discovery_errors = [ "This provider is no longer available as a replacement. Choose another provider." ]
      end
      response.headers["Cache-Control"] = "no-store"
      render partial: "source_migrations/matches", formats: [ :html ]
    end
  end

  def series_create
    @series = followed_series.find_by_param!(params[:series_slug])
    @from_source = @series.sources.find(params[:from_source_id])
    @to_source = Source.find(params[:to_source_id])

    if @from_source == @to_source
      redirect_to library_series_migration_path(series_slug: @series.to_param, from_source_id: @from_source.id), alert: "Choose a different replacement source."
      return
    end

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

    queue_replacement_checks(result, @to_source)

    if result.success && result.migrated.any?
      message = "Now using #{@to_source.name} for #{@series.canonical_title}. Checking for chapters in the background."
      variant = :success
    elsif result.success && result.already_on_target.any?
      message = "#{@series.canonical_title} was already using #{@to_source.name}"
      variant = :info
    else
      message = "Source unchanged. #{result.errors.first(3).join('; ').presence || 'No matching series was found.'}"
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

  def followed_series
    Series.where(library_series_id: current_user.user_series_follows.select(:library_series_id))
  end

  def preferred_source(series)
    priority = current_user.user_series_follows.find_by(library_series_id: series.library_series_id)&.source_priority || []
    sources = series.sources.to_a
    priority.filter_map { |key| sources.find { |source| source.key == key } }.first || series.primary_source || sources.first
  end

  def queue_replacement_checks(result, source)
    result.migrated.each do |series|
      follow = current_user.user_series_follows.find_by(library_series_id: series.library_series_id)
      CheckSourceForChaptersJob.perform_later(series.id, follow.id, source.id) if follow
    end
  end

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
end
