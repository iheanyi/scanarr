require "json"

module Scrapers
  module Mangadex
  class Adapter < Scrapers::BaseAdapter
    STATUS_FILTER_OPTIONS = [
      [ "Ongoing", "ongoing" ],
      [ "Completed", "completed" ],
      [ "Hiatus", "hiatus" ],
      [ "Cancelled", "cancelled" ]
    ].freeze
    FILTER_OPTIONS_CACHE_KEY = "scrapers/mangadex/filter_options".freeze
    FILTER_OPTIONS_CACHE_TTL = 12.hours

    def search(query, filters: {})
      response = http.get("/manga", params: {
        title: query,
        limit: 20,
        includes: [ "cover_art", "author" ]
      }.merge(mangadex_filter_params(filters)))
      payload = JSON.parse(response.body)
      payload.fetch("data", []).map do |item|
        attrs = item.fetch("attributes", {})
        title = pick_title(attrs.fetch("title", {}))
        cover = cover_url(item)
        authors = relationship_names(item, "author")
        ResultTypes::SearchResult.new(
          id: item.fetch("id"),
          title: title,
          url: "https://mangadex.org/title/#{item.fetch('id')}",
          cover_url: cover,
          language: attrs["originalLanguage"],
          author: authors.first
        )
      end
    end

    def supports_browse?
      true
    end

    def supports_server_side_filters?
      true
    end

    def search_filter_options
      {
        genres: genre_filter_options,
        statuses: STATUS_FILTER_OPTIONS
      }
    end

    def browse_filter_options
      search_filter_options
    end

    def browse_page_size
      48
    end

    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      order = case sort
      when "popular"
        { followedCount: "desc" }
      when "alphabetical"
        { title: "asc" }
      else # "latest"
        { latestUploadedChapter: "desc" }
      end

      offset = (page - 1) * limit

      response = http.get("/manga", params: {
        order: order,
        limit: limit,
        offset: offset,
        includes: [ "cover_art", "author" ]
      }.merge(mangadex_filter_params(filters)))

      payload = JSON.parse(response.body)
      payload.fetch("data", []).map do |item|
        attrs = item.fetch("attributes", {})
        title = pick_title(attrs.fetch("title", {}))
        cover = cover_url(item)
        authors = relationship_names(item, "author")

        ResultTypes::BrowseResult.new(
          id: item.fetch("id"),
          title: title,
          url: "https://mangadex.org/title/#{item.fetch('id')}",
          cover_url: cover,
          language: attrs["originalLanguage"],
          author: authors.first,
          status: attrs["status"],
          last_updated: attrs["updatedAt"],
          chapter_count: nil,
          description: pick_title(attrs.fetch("description", {}))
        )
      end
    end

    def series(id_or_url)
      id = extract_manga_id(id_or_url)
      response = http.get("/manga/#{id}", params: { includes: [ "cover_art", "author", "artist" ] })
      item = JSON.parse(response.body).fetch("data")
      attrs = item.fetch("attributes", {})
      authors = relationship_names(item, "author")
      artists = relationship_names(item, "artist")
      ResultTypes::Series.new(
        id: item.fetch("id"),
        title: pick_title(attrs.fetch("title", {})),
        alt_titles: attrs.fetch("altTitles", []).map { |t| t.values.first }.compact,
        description: pick_title(attrs.fetch("description", {})),
        author: authors.first,
        artist: artists.first,
        status: attrs["status"],
        tags: attrs.fetch("tags", []).map { |tag| pick_title(tag.fetch("attributes", {}).fetch("name", {})) }.compact,
        series_type: type_from_language(attrs["originalLanguage"]),
        cover_url: cover_url(item),
        url: "https://mangadex.org/title/#{item.fetch('id')}"
      )
    end

    def chapters(series_url, language: nil)
      id = extract_manga_id(series_url)
      chapters = []
      offset = 0
      limit = 100

      # Default to English, but allow override
      languages = language ? Array(language) : [ "en" ]

      loop do
        response = http.get(
          "/manga/#{id}/feed",
          params: {
            limit: limit,
            offset: offset,
            translatedLanguage: languages,
            # Include all content ratings to get all chapters
            contentRating: %w[safe suggestive erotica pornographic],
            order: { chapter: "asc" },
            # Include scanlation group info
            includes: [ "scanlation_group" ]
          }
        )
        payload = JSON.parse(response.body)

        if payload["result"] == "error"
          errors = payload["errors"]&.map { |e| e["detail"] }&.join(", ") || "Unknown error"
          Rails.logger.error "MangaDex chapters error: #{errors}"
          break
        end

        payload.fetch("data", []).each do |item|
          attrs = item.fetch("attributes", {})
          group_name = item.fetch("relationships", [])
                          .find { |r| r["type"] == "scanlation_group" }
                          &.dig("attributes", "name")

          chapters << ResultTypes::Chapter.new(
            id: item.fetch("id"),
            title: attrs["title"],
            number: attrs["chapter"],
            volume: attrs["volume"],
            language: attrs["translatedLanguage"],
            group: group_name,
            published_at: attrs["publishAt"],
            url: "https://mangadex.org/chapter/#{item.fetch('id')}"
          )
        end

        total = payload.fetch("total", chapters.size)
        Rails.logger.debug "MangaDex chapters: fetched #{chapters.size}/#{total} for manga #{id}"
        offset += limit
        break if offset >= total
      end

      # Deduplicate by chapter number, keeping newest version
      chapters
        .group_by(&:number)
        .values
        .map { |group| group.max_by { |c| c.published_at || "" } }
        .sort_by { |c| c.number.to_f rescue 0 }
    end

    def pages(chapter_url)
      id = extract_chapter_id(chapter_url)
      response = http.get("/at-home/server/#{id}")
      payload = JSON.parse(response.body)

      # Handle API errors
      if payload["result"] == "error"
        errors = payload["errors"]&.map { |e| e["detail"] }&.join(", ") || "Unknown error"

        # Check for specific error types
        if errors.include?("not found") || errors.include?("does not exist")
          raise Scrapers::Errors::ChapterNotFoundError, "Chapter is no longer available on MangaDex"
        elsif errors.include?("rate limit")
          raise Scrapers::Errors::RateLimitError, "MangaDex rate limit exceeded, please try again later"
        else
          raise Scrapers::Errors::ScraperError, "MangaDex error: #{errors}"
        end
      end

      base = payload["baseUrl"]
      chapter_data = payload["chapter"]

      if base.nil? || chapter_data.nil?
        Rails.logger.error "MangaDex unexpected response for chapter #{id}: #{payload.inspect}"
        raise Scrapers::Errors::SourceUnavailableError, "MangaDex returned an unexpected response"
      end

      hash = chapter_data.fetch("hash")
      files = chapter_data.fetch("data")

      files.map.with_index do |filename, idx|
        ResultTypes::Page.new(index: idx + 1, url: "#{base}/data/#{hash}/#{filename}", mime_type: nil)
      end
    end

    private

    def mangadex_filter_params(filters)
      return {} unless filters.is_a?(Hash)

      params = {}
      selected_genres = filter_values(filters, :genres)
      selected_statuses = filter_values(filters, :statuses) & STATUS_FILTER_OPTIONS.map(&:last)

      if selected_genres.present?
        params[:includedTags] = selected_genres
        params[:includedTagsMode] = "OR"
      end
      params[:status] = selected_statuses if selected_statuses.present?
      params
    end

    def genre_filter_options
      Rails.cache.fetch(FILTER_OPTIONS_CACHE_KEY, expires_in: FILTER_OPTIONS_CACHE_TTL) do
        response = http.get("/manga/tag")
        payload = JSON.parse(response.body)
        payload.fetch("data", []).filter_map do |tag|
          attributes = tag.fetch("attributes", {})
          next unless attributes["group"] == "genre"

          id = tag.fetch("id", "").to_s
          label = pick_title(attributes.fetch("name", {}))
          next if id.blank? || label.blank?

          [ label, id ]
        end.sort_by { |(label, _)| label.downcase }
      end
    rescue StandardError => e
      Rails.logger.warn "[Mangadex] Failed to fetch filter options: #{e.class} - #{e.message}"
      []
    end

    def filter_values(filters, key)
      raw_values = filters[key] || filters[key.to_s]
      Array(raw_values).filter_map do |value|
        normalized = value.to_s.strip
        normalized if normalized.present?
      end.uniq
    end

    def pick_title(title_hash)
      return nil if title_hash.nil?

      title_hash["en"] || title_hash.values.compact.first
    end

    def extract_manga_id(id_or_url)
      url = id_or_url.to_s
      return url if url.match?(/\A[0-9a-f-]{36}\z/i)

      url[/\/title\/([0-9a-f-]{36})/i, 1] || url
    end

    def extract_chapter_id(id_or_url)
      url = id_or_url.to_s
      return url if url.match?(/\A[0-9a-f-]{36}\z/i)

      url[/\/chapter\/([0-9a-f-]{36})/i, 1] || url
    end

    def cover_url(item)
      cover = item.fetch("relationships", []).find { |rel| rel["type"] == "cover_art" }
      filename = cover&.dig("attributes", "fileName")
      return nil if filename.nil?

      "https://uploads.mangadex.org/covers/#{item.fetch('id')}/#{filename}"
    end

    def relationship_names(item, type)
      item.fetch("relationships", [])
          .select { |rel| rel["type"] == type }
          .map { |rel| rel.dig("attributes", "name") }
          .compact
    end

    def type_from_language(lang)
      case lang.to_s
      when "ja"
        "manga"
      when "ko"
        "manhwa"
      when "zh"
        "manhua"
      else
        "manga"
      end
    end
  end
  end
end
