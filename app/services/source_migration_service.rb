# frozen_string_literal: true

class SourceMigrationService
  Result = Data.define(:success, :migrated, :no_match, :already_on_target, :errors)

  def initialize(from_source:, to_source:, user:)
    @from_source = from_source
    @to_source = to_source
    @user = user
    @migrated = []
    @no_match = []
    @already_on_target = []
    @errors = []
  end

  # Preview what would happen without making changes
  def preview
    affected_series.each do |series|
      if series.sources.include?(@to_source)
        @already_on_target << series
      else
        @no_match << series
      end
    end

    Result.new(
      success: true,
      migrated: [],
      no_match: @no_match,
      already_on_target: @already_on_target,
      errors: []
    )
  end

  # Execute the migration
  def execute!
    ActiveRecord::Base.transaction do
      affected_series.each do |series|
        migrate_series(series)
      end
    end

    Result.new(
      success: @errors.empty?,
      migrated: @migrated,
      no_match: @no_match,
      already_on_target: @already_on_target,
      errors: @errors
    )
  rescue => e
    @errors << e.message
    Result.new(
      success: false,
      migrated: @migrated,
      no_match: @no_match,
      already_on_target: @already_on_target,
      errors: @errors
    )
  end

  private

  def affected_series
    @affected_series ||= begin
      series_ids = @from_source.series
        .joins(library_series: :user_series_follows)
        .where(user_series_follows: { user: @user })
        .select("series.id")
        .distinct
        .pluck(:id)

      Series.where(id: series_ids).includes(:sources, :series_sources)
    end
  end

  def migrate_series(series)
    if series.sources.include?(@to_source)
      # Already has target source — just update priority
      update_source_priority(series)
      @already_on_target << series
    else
      # Series doesn't exist on target source — can't auto-migrate
      @no_match << series
    end
  rescue => e
    @errors << "#{series.canonical_title}: #{e.message}"
  end

  def update_source_priority(series)
    follow = @user.user_series_follows
      .joins(:library_series)
      .where(library_series: { id: series.library_series_id })
      .first
    return unless follow

    priority = follow.source_priority || []

    # Remove the old source from priority and add the new one at the top
    priority = priority.reject { |k| k == @from_source.key }
    priority.unshift(@to_source.key) unless priority.include?(@to_source.key)

    follow.update!(source_priority: priority)
    @migrated << series
  end
end
