class SearchController < ApplicationController
  SEARCH_TIMEOUT_SECONDS = 8
  MAX_SEARCH_WORKERS = 6
  STATUS_OPTIONS = [
    [ "Any reading state", "" ],
    [ "Downloaded", "downloaded" ],
    [ "In Progress", "in_progress" ],
    [ "Not Started", "not_started" ],
    [ "Completed", "completed" ],
    [ "Following", "following" ]
  ].freeze

  def index
    @include_mature = ActiveModel::Type::Boolean.new.cast(params[:include_mature])
    # Broken/dead sources are excluded from fan-out: each one would burn the
    # full search timeout for results we know it cannot deliver.
    all_sources = Source.where(enabled: true)
      .where.not(health_status: %w[broken dead])
      .order(:name, :key).to_a
    @mature_source_count = all_sources.count(&:mature_content?)
    @sources = @include_mature ? all_sources : all_sources.reject(&:mature_content?)
    @hidden_mature_count = @include_mature ? 0 : @mature_source_count

    @query = params[:q].to_s.strip
    @selected_source_ids = normalized_selected_source_ids
    @genre_options = available_genre_options
    @genres = normalized_genres
    @status_options = STATUS_OPTIONS
    @status = normalized_status_param

    @results = []
    @errors = []
    return if @query.blank?

    selected_sources = @sources.select { |source| @selected_source_ids.include?(source.id.to_s) }
    search_sources(selected_sources)
    attach_library_series_to_results! if advanced_filters_active?
    apply_advanced_filters!
    sort_results_by_chapter_count!
  end

  private

  def normalized_selected_source_ids
    visible_ids = @sources.map { |source| source.id.to_s }
    requested_ids = Array(params[:sources]).map { |value| value.to_s.strip }.reject(&:blank?)
    return visible_ids if requested_ids.empty?

    requested_ids & visible_ids
  end

  def normalized_genres
    Array(params[:genres]).filter_map do |genre|
      normalized = genre.to_s.strip.downcase.first(80)
      normalized if normalized.present?
    end.uniq
  end

  def normalized_status_param
    status = params[:status].to_s
    valid_statuses = STATUS_OPTIONS.map { |(_, value)| value }.reject(&:blank?)
    valid_statuses.include?(status) ? status : ""
  end

  def available_genre_options
    ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT DISTINCT jsonb_array_elements_text(normalized_categories) AS genre
      FROM series
      WHERE jsonb_typeof(normalized_categories) = 'array'
        AND jsonb_array_length(normalized_categories) > 0
      ORDER BY genre ASC
      LIMIT 200
    SQL
  end

  def advanced_filters_active?
    @genres.present? || @status.present?
  end

  def search_sources(sources)
    return if sources.empty?

    worker_count = [ sources.size, MAX_SEARCH_WORKERS ].min
    executor = Concurrent::FixedThreadPool.new(worker_count)
    futures = []
    begin
      futures = sources.map do |source|
        Concurrent::Promises.future_on(executor, source) do |target_source|
          search_source(target_source)
        end
      end

      futures.each_with_index do |future, index|
        source = sources[index]
        payload = future.value!(SEARCH_TIMEOUT_SECONDS)
        if payload.nil?
          @errors << { source: source, message: "Search timed out" }
          Rails.logger.warn "Search timed out for #{source.key}"
          next
        end

        @results.concat(payload[:results])
        @errors << payload[:error] if payload[:error]
      rescue StandardError => e
        @errors << { source: source, message: e.message.truncate(100) }
        Rails.logger.warn "Search failed for #{source.key}: #{e.class} - #{e.message}"
      end
    ensure
      executor.shutdown
      executor.wait_for_termination(1)
    end
  end

  def search_source(source)
    unless Scrapers::AdapterRegistry.registered?(source.key)
      return { results: [], error: { source: source, message: "Adapter not implemented" } }
    end

    adapter = Scrapers::AdapterRegistry.for(source)
    results = adapter.search(@query).map do |result|
      { source: source, result: result }
    end
    { results: results, error: nil }
  rescue Scrapers::AdapterRegistry::UnknownSourceError => e
    Rails.logger.warn "Search skipped for #{source.key}: #{e.message}"
    { results: [], error: { source: source, message: "Source not configured" } }
  rescue StandardError => e
    Rails.logger.warn "Search failed for #{source.key}: #{e.class} - #{e.message}"
    { results: [], error: { source: source, message: e.message.truncate(100) } }
  end

  def attach_library_series_to_results!
    lookup_pairs = @results.filter_map do |item|
      source_id = item[:source]&.id
      source_series_id = item[:result]&.id.to_s
      next if source_id.blank? || source_series_id.blank?

      [ source_id, source_series_id ]
    end.uniq
    return if lookup_pairs.empty?

    source_ids = lookup_pairs.map(&:first).uniq
    source_series_ids = lookup_pairs.map(&:second).uniq
    series_sources = SeriesSource.includes(:series).where(source_id: source_ids, source_series_id: source_series_ids)
    series_by_source = series_sources.index_by { |series_source| [ series_source.source_id, series_source.source_series_id.to_s ] }

    @results.each do |item|
      source_id = item[:source]&.id
      source_series_id = item[:result]&.id.to_s
      item[:library_series] = series_by_source[[ source_id, source_series_id ]]&.series
    end
  end

  def apply_advanced_filters!
    return unless advanced_filters_active?

    filter_results_by_genre! if @genres.present?
    filter_results_by_status! if @status.present?
  end

  def filter_results_by_genre!
    @results.select! do |item|
      library_series = item[:library_series]
      next false unless library_series

      series_genres = Array(library_series.normalized_categories).map { |genre| genre.to_s.downcase }
      (@genres & series_genres).any?
    end
  end

  def filter_results_by_status!
    allowed_series_ids = filtered_series_ids_for_status
    @results.select! do |item|
      library_series = item[:library_series]
      library_series && allowed_series_ids.include?(library_series.id)
    end
  end

  def filtered_series_ids_for_status
    mapped_series_ids = @results.filter_map { |item| item[:library_series]&.id }.uniq
    return [] if mapped_series_ids.empty?

    case @status
    when "downloaded"
      FileAsset.where(download_status: "complete")
               .joins(release: :chapter)
               .where(chapters: { series_id: mapped_series_ids })
               .distinct
               .pluck("chapters.series_id")
    when "in_progress"
      FileAsset.where(download_status: %w[downloading queued pending])
               .joins(release: :chapter)
               .where(chapters: { series_id: mapped_series_ids })
               .distinct
               .pluck("chapters.series_id")
    when "not_started"
      return [] unless current_user

      started_series_ids = ChapterProgress.where(user: current_user)
                                          .joins(:chapter)
                                          .where(chapters: { series_id: mapped_series_ids })
                                          .distinct
                                          .pluck("chapters.series_id")
      mapped_series_ids - started_series_ids
    when "completed"
      return [] unless current_user

      ChapterProgress.where(user: current_user, status: "completed")
                     .joins(:chapter)
                     .where(chapters: { series_id: mapped_series_ids })
                     .distinct
                     .pluck("chapters.series_id")
    when "following"
      return [] unless current_user

      followed_library_series_ids = current_user.user_series_follows.pluck(:library_series_id)
      Series.where(id: mapped_series_ids, library_series_id: followed_library_series_ids).pluck(:id)
    else
      mapped_series_ids
    end
  end

  def sort_results_by_chapter_count!
    @results.sort_by! do |item|
      chapter_count = item[:result].respond_to?(:chapter_count) ? item[:result].chapter_count : nil
      [ chapter_count.nil? ? 1 : 0, -(chapter_count || 0), item[:result].title.to_s.downcase ]
    end
  end

  def current_search_params(overrides = {})
    params_hash = {
      q: @query.presence,
      sources: @selected_source_ids.presence,
      genres: @genres.presence,
      status: @status.presence,
      include_mature: @include_mature ? "1" : nil
    }.compact
    params_hash.merge!(overrides)
    params_hash.delete_if { |_, value| value.blank? }
    params_hash
  end

  def status_label_for(status_key)
    STATUS_OPTIONS.to_h.invert[status_key.to_s] || status_key.to_s.tr("_", " ").titleize
  end

  def source_slug(source)
    source.slug
  end
  helper_method :source_slug, :current_search_params, :status_label_for
end
