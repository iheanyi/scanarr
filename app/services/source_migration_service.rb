# frozen_string_literal: true

class SourceMigrationService
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
    @migrated = []
    @no_match = []
    @already_on_target = []
    @errors = []
  end

  # Preview what would happen without making changes or network calls.
  # Unlinked series are auto-link candidates, not failures: execute! will
  # search the target for them and link exact title matches, so the preview
  # must represent that attempt rather than declaring no_match up front.
  def preview
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

  def migrate_series(series)
    if series.sources.include?(@to_source)
      # Already has target source — just update priority
      update_source_priority(series)
      @already_on_target << series
    elsif auto_link_series(series)
      update_source_priority(series)
      @migrated << series unless @migrated.include?(series)
    else
      @no_match << series
    end
  rescue => e
    @errors << "#{series.canonical_title}: #{e.message}"
  end

  # Search the target source for the series and link it when the best result
  # clears the auto-link confidence bar. Below the bar, the series stays
  # no_match for the user to resolve manually via discovery.
  def auto_link_series(series)
    return false unless @auto_link
    return false unless @adapter_registry.registered?(@to_source.key)

    adapter = @adapter_registry.for(@to_source)
    results = adapter.search(series.canonical_title).first(5)
    match, _confidence = Sources::TitleMatcher.best_match(
      series.canonical_title,
      results,
      min_confidence: Sources::TitleMatcher::AUTO_LINK_CONFIDENCE
    )
    return false unless match

    target_series = adapter.series(match.url)
    source_series_id = target_series.id.to_s.strip
    return false if source_series_id.blank?

    series.series_sources.create!(source: @to_source, source_series_id: source_series_id)
    series.sources.reset
    true
  rescue Scrapers::Errors::ScraperError, Scrapers::AdapterRegistry::UnknownSourceError => e
    @errors << "#{series.canonical_title}: #{e.message}"
    false
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
