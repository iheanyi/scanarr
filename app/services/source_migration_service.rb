# frozen_string_literal: true

require "timeout"

class SourceMigrationService
  # Bound per-series network time so one hanging target source cannot tie up
  # the migration request and starve the remaining series.
  AUTO_LINK_TIMEOUT_SECONDS = 20
  Result = Data.define(:success, :migrated, :no_match, :already_on_target, :link_candidates, :errors)

  def initialize(from_source:, to_source:, user:, series_ids: nil, auto_link: true, adapter_registry: Scrapers::AdapterRegistry)
    @from_source = from_source
    @to_source = to_source
    @user = user
    @auto_link = auto_link
    @adapter_registry = adapter_registry
    @selected_series_ids = if series_ids.nil?
      nil
    else
      Array(series_ids).filter_map { |id| Integer(id, exception: false) }.uniq
    end
    reset_results
  end

  # Preview what would happen without making changes or network calls.
  # Unlinked series are auto-link candidates, not failures: execute! will
  # search the target for them and link exact title matches, so the preview
  # must represent that attempt rather than declaring no_match up front.
  def preview
    reset_results
    return unusable_target_result if target_unusable?

    link_candidates = []

    affected_series.each do |series|
      if series.sources.include?(@to_source)
        @already_on_target << series
      elsif @auto_link
        link_candidates << series
      else
        @no_match << series
      end
    end

    Result.new(
      success: true,
      migrated: [],
      no_match: @no_match,
      already_on_target: @already_on_target,
      link_candidates: link_candidates,
      errors: []
    )
  end

  # Execute the migration. Each series migrates independently so one failure
  # (or a slow source) cannot roll back or block the rest; re-running
  # converges because linked series take the already_on_target path.
  def execute!
    reset_results
    return unusable_target_result if target_unusable?

    affected_series.each do |series|
      migrate_series(series)
    end

    Result.new(
      success: @errors.empty?,
      migrated: @migrated,
      no_match: @no_match,
      already_on_target: @already_on_target,
      link_candidates: [],
      errors: @errors
    )
  rescue => e
    @errors << e.message
    Result.new(
      success: false,
      migrated: @migrated,
      no_match: @no_match,
      already_on_target: @already_on_target,
      link_candidates: [],
      errors: @errors
    )
  end

  private

  def reset_results
    @migrated = []
    @no_match = []
    @already_on_target = []
    @errors = []
    @affected_series = nil
  end

  # Migrating FROM a broken source is the whole point of migration; migrating
  # TO a broken, dead, or operator-disabled one would search and prioritize a
  # source the rest of the app skips.
  def target_unusable?
    @from_source == @to_source || @to_source.migration_target_rejection.present?
  end

  def unusable_target_result
    reason = @to_source.migration_target_rejection
    message = if @from_source == @to_source
      "Choose a replacement source different from the current source"
    else
      "#{@to_source.name} is #{reason} and cannot be a migration target"
    end
    Result.new(
      success: false,
      migrated: [],
      no_match: [],
      already_on_target: [],
      link_candidates: [],
      errors: [ message ]
    )
  end

  def affected_series
    @affected_series ||= begin
      followed_series_ids = @from_source.series
        .joins(library_series: :user_series_follows)
        .where(user_series_follows: { user: @user })
        .select("series.id")
        .distinct
        .pluck(:id)

      series_ids = if @selected_series_ids.nil?
        followed_series_ids
      else
        followed_series_ids & @selected_series_ids
      end

      Series.where(id: series_ids).includes(:sources, :series_sources)
    end
  end

  # Buckets are disjoint: a linked series whose priority moves counts as
  # migrated, one with nothing to change is already_on_target. The completion
  # toast sums them, so a series must never appear in both.
  def migrate_series(series)
    if series.sources.include?(@to_source)
      @already_on_target << series unless update_source_priority(series)
    elsif auto_link_series(series)
      update_source_priority(series)
      @migrated << series unless @migrated.include?(series)
    else
      @no_match << series
    end
  rescue => e
    @errors << "#{series.canonical_title}: #{e.message}"
  end

  # Only a unique exact title match can link unattended. Distinct editions
  # with the same title need a human choice, even when both score perfectly.
  def auto_link_series(series)
    return false unless @auto_link
    return false unless @adapter_registry.registered?(@to_source.key)

    adapter = @adapter_registry.for(@to_source)
    source_series_id = Timeout.timeout(AUTO_LINK_TIMEOUT_SECONDS) do
      matches = adapter.search(series.canonical_title).select do |result|
        Sources::TitleMatcher.score(series.canonical_title, result.title) >= Sources::TitleMatcher::AUTO_LINK_CONFIDENCE
      end.uniq { |result| result.id.presence || result.url }
      matches.one? ? adapter.series(matches.first.url).id.to_s.strip : nil
    end
    return false if source_series_id.blank?

    series.series_sources.create!(source: @to_source, source_series_id: source_series_id)
    series.sources.reset
    true
  rescue Timeout::Error
    @errors << "#{series.canonical_title}: timed out searching #{@to_source.name}"
    false
  rescue Scrapers::Errors::ScraperError, Scrapers::AdapterRegistry::UnknownSourceError => e
    @errors << "#{series.canonical_title}: #{e.message}"
    false
  end

  def update_source_priority(series)
    follow = @user.user_series_follows
      .joins(:library_series)
      .where(library_series: { id: series.library_series_id })
      .first
    return false unless follow

    follow.with_lock do
      # Existing target links may already be lower in the preference list.
      # Always move the replacement first, preserving unrelated fallbacks.
      priority = [ @to_source.key ] + Array(follow.source_priority)
        .reject { |key| key == @from_source.key || key == @to_source.key }
        .uniq
      return false if follow.source_priority == priority

      follow.update!(source_priority: priority)
      @migrated << series
      true
    end
  end
end
