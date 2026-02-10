class SourcesController < ApplicationController
  before_action :set_source, only: %i[search browse preview preview_read preview_image import]

  helper_method :source_slug, :preview_image_token_for, :source_search_params, :source_browse_params, :source_filter_label

  SORT_OPTIONS = {
    "name_asc" => "Name A–Z",
    "name_desc" => "Name Z–A",
    "most_series" => "Most Series"
  }.freeze
  PREVIEW_CHAPTER_LIMIT = 50
  PREVIEW_IMAGE_TOKEN_PURPOSE = "source_preview_image".freeze
  PREVIEW_IMAGE_TOKEN_TTL = 6.hours
  FILTER_OPTION_KEYS = %i[genres statuses].freeze

  def index
    @sort_by = params[:sort_by].presence || "name_asc"
    @sort_options = SORT_OPTIONS
    @include_mature = ActiveModel::Type::Boolean.new.cast(params[:include_mature])

    scope = Source.where(enabled: true)
    ordered_sources = case @sort_by
    when "name_desc"
                 scope.order(name: :desc)
    when "most_series"
                 scope.left_joins(:series_sources)
                      .group("sources.id")
                      .order(Arel.sql("COUNT(series_sources.id) DESC"), name: :asc)
    else # name_asc
                 scope.order(name: :asc)
    end.to_a

    @mature_source_count = ordered_sources.count(&:mature_content?)
    @sources = @include_mature ? ordered_sources : ordered_sources.reject(&:mature_content?)
    @hidden_mature_count = @include_mature ? 0 : @mature_source_count
  end

  def browse
    @sort = params[:sort].presence || "latest"
    @page = [ (params[:page].presence || 1).to_i, 1 ].max
    @results = []
    @error = nil
    @selected_genres = []
    @selected_statuses = []
    @browse_filter_options = empty_filter_options
    @supports_server_side_filters = false

    unless Scrapers::AdapterRegistry.registered?(@source.key)
      @error = "This source doesn't have an adapter yet"
      return
    end

    adapter = Scrapers::AdapterRegistry.for(@source)

    unless adapter.supports_browse?
      @error = "This source doesn't support browsing yet"
      return
    end

    @page_size = adapter.browse_page_size
    @sort_options = adapter.browse_sort_options
    @sort = @sort_options.first unless @sort_options.include?(@sort)
    configure_browse_filters(adapter)
    browse_filters = selected_adapter_filters(@selected_genres, @selected_statuses)
    @results = if @supports_server_side_filters && browse_filters.present?
      adapter.browse(sort: @sort, page: @page, limit: @page_size, filters: browse_filters)
    else
      adapter.browse(sort: @sort, page: @page, limit: @page_size)
    end
  rescue Scrapers::Errors::BrowseNotSupportedError => e
    @error = e.message
  rescue StandardError => e
    @error = "Browse failed: #{e.message}"
    Rails.logger.warn "Browse failed for #{@source.key}: #{e.class} - #{e.message}"
  end

  def preview
    @series_url = params[:series_url].to_s
    @series = nil
    @chapters = []
    @error = nil

    if @series_url.blank?
      @error = "No series URL provided"
      return
    end

    unless Scrapers::AdapterRegistry.registered?(@source.key)
      @error = "This source doesn't have an adapter yet"
      return
    end

    adapter = Scrapers::AdapterRegistry.for(@source)
    @series = adapter.series(@series_url)
    @chapters = adapter.chapters(@series_url).first(10) # Preview first 10 chapters
  rescue Scrapers::Errors::SeriesNotFoundError => e
    @error = "Series not found: #{e.message}"
  rescue StandardError => e
    @error = "Failed to load series: #{e.message}"
    Rails.logger.warn "Preview failed for #{@source.key}: #{e.class} - #{e.message}"
  end

  def preview_read
    @series_url = params[:series_url].to_s
    @chapter_url = params[:chapter_url].to_s
    @series = nil
    @chapters = []
    @chapter = nil
    @previous_chapter = nil
    @next_chapter = nil
    @source_pages = []
    @source_error = nil
    @error = nil
    @reading_style = preview_reading_style(params[:reading_style])
    @initial_page_index = preview_initial_page_index(params[:page])

    if @series_url.blank? || @chapter_url.blank?
      @error = "Series URL and chapter URL are required"
      return
    end

    unless Scrapers::AdapterRegistry.registered?(@source.key)
      @error = "This source doesn't have an adapter yet"
      return
    end

    adapter = Scrapers::AdapterRegistry.for(@source)
    @series = adapter.series(@series_url)
    @chapters = adapter.chapters(@series_url).first(PREVIEW_CHAPTER_LIMIT)
    @chapter = @chapters.find { |chapter| chapter.url == @chapter_url } || build_preview_chapter_fallback(@chapter_url)
    @previous_chapter, @next_chapter = preview_navigation_for(@chapters, @chapter)
    @source_pages = adapter.pages(@chapter_url)
  rescue Scrapers::Errors::SeriesNotFoundError => e
    @error = "Series not found: #{e.message}"
  rescue Scrapers::Errors::ChapterNotFoundError => e
    @source_error = "This chapter is no longer available on the source. It may have been removed or replaced."
    Rails.logger.warn "Preview read chapter not found for #{@source.key}: #{e.class} - #{e.message}"
  rescue Scrapers::Errors::RateLimitError => e
    @source_error = "The source is rate limiting requests. Please try again in a few minutes."
    Rails.logger.warn "Preview read rate limited for #{@source.key}: #{e.class} - #{e.message}"
  rescue Scrapers::Errors::SourceUnavailableError, Scrapers::Errors::ScraperError => e
    @source_error = "Unable to load pages from source: #{e.message}"
    Rails.logger.warn "Preview read failed for #{@source.key}: #{e.class} - #{e.message}"
  rescue StandardError => e
    @error = "Failed to load chapter preview: #{e.message}"
    Rails.logger.warn "Preview read failed for #{@source.key}: #{e.class} - #{e.message}"
  end

  def preview_image
    token_payload = preview_image_payload(params[:token])
    return head :forbidden if token_payload.blank?

    page_url = token_payload.fetch("page_url", "").to_s
    source_slug = token_payload.fetch("source_slug", "").to_s
    return head :forbidden if page_url.blank? || source_slug != @source.slug

    unless Scrapers::AdapterRegistry.registered?(@source.key)
      return head :not_found
    end

    adapter = Scrapers::AdapterRegistry.for(@source)
    response = adapter.http.get(page_url)

    unless response.status.to_i == 200
      Rails.logger.warn "Preview image proxy failed for #{@source.key}: status=#{response.status} url=#{page_url}"
      return head :bad_gateway
    end

    content_type = response.headers["content-type"].to_s
    content_type = "application/octet-stream" if content_type.blank?
    send_data response.body, type: content_type, disposition: "inline"
  rescue StandardError => e
    Rails.logger.warn "Preview image proxy error for #{@source.key}: #{e.class} - #{e.message}"
    head :bad_gateway
  end

  def search
    @query = params[:q].to_s.strip
    @results = []
    @error = nil
    @selected_genres = []
    @selected_statuses = []
    @search_filter_options = empty_filter_options
    @supports_server_side_filters = false

    unless Scrapers::AdapterRegistry.registered?(@source.key)
      @error = "This source doesn't have a search adapter yet"
      return
    end

    adapter = Scrapers::AdapterRegistry.for(@source)
    supports_search = adapter.respond_to?(:supports_search?) ? adapter.supports_search? : true
    unless supports_search
      @error = "This source doesn't support searching yet"
      return
    end

    configure_search_filters(adapter)
    return if @query.blank?

    search_filters = selected_adapter_filters(@selected_genres, @selected_statuses)
    @results = if @supports_server_side_filters && search_filters.present?
      adapter.search(@query, filters: search_filters)
    else
      adapter.search(@query)
    end
  rescue StandardError => e
    @error = "Search failed: #{e.message}"
    Rails.logger.warn "Search failed for #{@source.key}: #{e.class} - #{e.message}"
  end

  def import
    series_url = params[:series_url].to_s
    if series_url.blank?
      redirect_to source_search_path(source_slug: source_slug(@source)), alert: "No series URL provided" and return
    end

    unless Scrapers::AdapterRegistry.registered?(@source.key)
      redirect_to search_path, alert: "Import not available for this source" and return
    end

    importer = SeriesImporter.new(source: @source, adapter: Scrapers::AdapterRegistry.for(@source))
    series = importer.import!(series_url)
    chapter_count = series.chapters.where(source: @source).count

    # Ensure library series exists for the follow button
    series.ensure_library_series!

    # Auto-follow for the importing user
    follow = current_user.user_series_follows.find_or_create_by!(library_series: series.library_series) do |follow|
      follow.download_policy = current_user.effective_download_policy
    end

    if follow.auto_download?
      DownloadAllJob.perform_later(series.id, @source.id)
      flash[:notice] = "Imported \"#{series.canonical_title}\" with #{chapter_count} #{'chapter'.pluralize(chapter_count)} and queued downloads."
    else
      flash[:notice] = "Imported \"#{series.canonical_title}\" with #{chapter_count} #{'chapter'.pluralize(chapter_count)}."
    end
    redirect_to library_series_path(series_slug: series.to_param)
  rescue Scrapers::Errors::ScraperError, StandardError => e
    Rails.logger.error "Import failed for #{series_url}: #{e.class} - #{e.message}"
    redirect_to search_path(q: params[:q]), alert: "Import failed: #{e.message}"
  end

  private

  def configure_search_filters(adapter)
    @supports_server_side_filters = adapter.respond_to?(:supports_server_side_filters?) && adapter.supports_server_side_filters?
    raw_options = adapter.respond_to?(:search_filter_options) ? adapter.search_filter_options : {}
    @search_filter_options = normalized_filter_options(raw_options)
    @selected_genres = normalized_filter_values(params[:genres], @search_filter_options[:genres])
    @selected_statuses = normalized_filter_values(params[:statuses], @search_filter_options[:statuses])
  end

  def configure_browse_filters(adapter)
    @supports_server_side_filters = adapter.respond_to?(:supports_server_side_filters?) && adapter.supports_server_side_filters?
    raw_options = adapter.respond_to?(:browse_filter_options) ? adapter.browse_filter_options : {}
    @browse_filter_options = normalized_filter_options(raw_options)
    @selected_genres = normalized_filter_values(params[:genres], @browse_filter_options[:genres])
    @selected_statuses = normalized_filter_values(params[:statuses], @browse_filter_options[:statuses])
  end

  def normalized_filter_options(raw_options)
    options = raw_options.is_a?(Hash) ? raw_options.deep_symbolize_keys : {}
    FILTER_OPTION_KEYS.index_with do |key|
      normalized_filter_entries(options[key])
    end
  end

  def normalized_filter_entries(entries)
    Array(entries).filter_map do |entry|
      label, value = if entry.is_a?(Array) && entry.size >= 2
        [ entry[0], entry[1] ]
      else
        normalized_value = entry.to_s.strip
        [ normalized_value.tr("_-", "  ").squish.titleize, normalized_value ]
      end

      normalized_label = label.to_s.strip
      normalized_value = value.to_s.strip
      next if normalized_label.blank? || normalized_value.blank?

      [ normalized_label, normalized_value ]
    end.uniq { |(_, value)| value }
  end

  def normalized_filter_values(values, options)
    allowed_values = options.map(&:last)
    return [] if allowed_values.empty?

    Array(values).filter_map do |value|
      normalized = value.to_s.strip
      normalized if normalized.present? && allowed_values.include?(normalized)
    end.uniq
  end

  def selected_adapter_filters(genres, statuses)
    {}.tap do |filters|
      filters[:genres] = genres if genres.present?
      filters[:statuses] = statuses if statuses.present?
    end
  end

  def source_search_params(overrides = {})
    params_hash = {
      source_slug: source_slug(@source),
      q: @query.presence,
      genres: @selected_genres.presence,
      statuses: @selected_statuses.presence
    }.compact
    params_hash.merge!(overrides)
    params_hash.delete_if { |_, value| value.blank? }
    params_hash
  end

  def source_browse_params(overrides = {})
    params_hash = {
      source_slug: source_slug(@source),
      sort: @sort.presence,
      page: @page.presence,
      genres: @selected_genres.presence,
      statuses: @selected_statuses.presence
    }.compact
    params_hash.merge!(overrides)
    params_hash.delete_if { |_, value| value.blank? }
    params_hash
  end

  def source_filter_label(kind, value)
    option_sets = @search_filter_options.presence || @browse_filter_options.presence || empty_filter_options
    labels_by_value = option_sets.fetch(kind.to_sym, []).to_h.invert
    labels_by_value[value.to_s] || value.to_s.tr("_-", " ").titleize
  end

  def empty_filter_options
    FILTER_OPTION_KEYS.index_with { [] }
  end

  def preview_image_token_for(page_url)
    return "" if page_url.blank?

    preview_image_verifier.generate(
      {
        source_slug: @source.slug,
        page_url: page_url
      },
      purpose: PREVIEW_IMAGE_TOKEN_PURPOSE,
      expires_in: PREVIEW_IMAGE_TOKEN_TTL
    )
  end

  def preview_image_payload(token)
    return nil if token.blank?

    preview_image_verifier.verified(token, purpose: PREVIEW_IMAGE_TOKEN_PURPOSE)
  end

  def preview_image_verifier
    Rails.application.message_verifier(:source_preview_image)
  end

  def preview_navigation_for(chapters, chapter)
    return [ nil, nil ] if chapter.nil? || chapter.url.blank?

    index = chapters.find_index { |entry| entry.url == chapter.url }
    return [ nil, nil ] unless index

    previous_chapter = index.positive? ? chapters[index - 1] : nil
    next_chapter = index < chapters.length - 1 ? chapters[index + 1] : nil
    [ previous_chapter, next_chapter ]
  end

  def build_preview_chapter_fallback(chapter_url)
    ResultTypes::Chapter.new(
      id: chapter_url,
      title: nil,
      number: nil,
      url: chapter_url
    )
  end

  def preview_reading_style(value)
    ReadingStyles.normalize(value)
  end

  def preview_initial_page_index(value)
    page = value.to_i
    page.positive? ? page : 1
  end

  def set_source
    @source = Source.find_by!(slug: params[:source_slug])
  end

  def source_slug(source)
    source.slug
  end
end
