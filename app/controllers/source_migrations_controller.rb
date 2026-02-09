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
      user: current_user
    ).preview

    @from_source = from_source
    @to_source = to_source
    @result = result

    render :preview, status: :unprocessable_entity
  end

  def create
    from_source = Source.find(params[:from_source_id])
    to_source = Source.find(params[:to_source_id])

    result = SourceMigrationService.new(
      from_source: from_source,
      to_source: to_source,
      user: current_user
    ).execute!

    if result.success
      flash[:notice] = "Migration complete! #{result.migrated.size} series migrated, " \
                        "#{result.already_on_target.size} already on target, " \
                        "#{result.no_match.size} could not be matched."
    else
      flash[:alert] = "Migration had errors: #{result.errors.first(3).join('; ')}"
    end

    redirect_to source_migrations_path
  end
end
