require "json"
require "nokogiri"

module Scrapers
  module Comick
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://comick.live"
    IMAGE_CDN = "https://meo.comick.pictures"

    # Status codes from the Comick API
    STATUS_MAP = {
      1 => "ongoing",
      2 => "completed",
      3 => "cancelled",
      4 => "hiatus"
    }.freeze

    def supports_browse?
      true
    end

    def browse_page_size
      30
    end

    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = filters
      case sort
      when "popular"
        browse_popular(page: page, limit: limit)
      when "alphabetical"
        browse_search(sort: "title", page: page, limit: limit)
      else # "latest"
        browse_latest(page: page, limit: limit)
      end
    end

    def search(query, filters: {})
      _ = filters
      response = http.get("/api/search", params: { q: query, type: "comic", limit: 20 })
      payload = parse_json_response(response, endpoint: "/api/search")

      results = payload.is_a?(Hash) ? payload.fetch("data", []) : payload
      results.map do |item|
        ResultTypes::SearchResult.new(
          id: item["slug"],
          title: item["title"],
          url: comic_url(item["slug"]),
          cover_url: item["default_thumbnail"],
          language: nil,
          author: nil
        )
      end
    end

    def series(id_or_url)
      slug = extract_slug(id_or_url)
      response = http.get("/comic/#{slug}")
      doc = Nokogiri::HTML(response.body)

      script = doc.at_css("#comic-data")
      raise Scrapers::Errors::SeriesNotFoundError, "Could not find comic data for #{slug}" unless script

      data = JSON.parse(script.text)

      authors = (data["authors"] || []).map { |a| a["name"] }
      artists = (data["artists"] || []).map { |a| a["name"] }
      genres = (data["md_comic_md_genres"] || []).filter_map { |g| g.dig("md_genres", "name") }
      alt_titles = extract_alt_titles(data["md_titles"])
      status_code = data["status"]
      status = STATUS_MAP.fetch(status_code, "ongoing")

      # If translation is completed but source is ongoing, keep as completed
      status = "completed" if data["translation_completed"] && status_code == 1

      description = data["desc"]
      description = Nokogiri::HTML.fragment(description).text if description

      ResultTypes::Series.new(
        id: slug,
        title: data["title"],
        alt_titles: alt_titles,
        description: description,
        author: authors.first,
        artist: artists.first,
        status: status,
        tags: genres,
        series_type: type_from_country(data["country"]),
        cover_url: data["default_thumbnail"],
        url: comic_url(slug)
      )
    end

    def chapters(series_url)
      slug = extract_slug(series_url)
      all_chapters = []
      page = 1

      loop do
        response = http.get("/api/comics/#{slug}/chapter-list", params: { lang: "en", page: page })
        payload = parse_json_response(response, endpoint: "/api/comics/#{slug}/chapter-list")

        data = payload.fetch("data", [])
        pagination = payload.fetch("pagination", {})

        data.each do |item|
          group = Array(item["group_name"]).first
          chapter_number = item["chap"]
          hid = item["hid"]

          all_chapters << ResultTypes::Chapter.new(
            id: hid,
            title: build_chapter_title(chapter_number, item["vol"], item["title"]),
            number: chapter_number,
            volume: item["vol"],
            language: item["lang"] || "en",
            group: group,
            published_at: item["created_at"],
            url: chapter_url(slug, hid, chapter_number, item["lang"] || "en")
          )
        end

        current_page = pagination["current_page"] || page
        last_page = pagination["last_page"] || 1
        break if current_page >= last_page

        page += 1
      end

      all_chapters
    end

    def pages(chapter_url)
      response = http.get(chapter_url)
      doc = Nokogiri::HTML(response.body)

      script = doc.at_css("#sv-data")
      raise Scrapers::Errors::ChapterNotFoundError, "Could not find chapter data for #{chapter_url}" unless script

      data = JSON.parse(script.text)
      images = data.dig("chapter", "images") || []

      images.map.with_index do |img, idx|
        ResultTypes::Page.new(
          index: idx + 1,
          url: img["url"],
          mime_type: nil
        )
      end
    end

    private

    def comic_url(slug)
      "#{base_url}/comic/#{slug}"
    end

    def chapter_url(manga_slug, hid, chapter_number, lang)
      "#{base_url}/comic/#{manga_slug}/#{hid}-chapter-#{chapter_number}-#{lang}"
    end

    def extract_slug(id_or_url)
      url = id_or_url.to_s

      # Handle full URLs: https://comick.live/comic/one-piece or similar
      if url.include?("/comic/")
        # Extract slug, stripping any chapter path after it
        path = url.split("/comic/").last
        return path.split("/").first
      end

      # Already a slug
      url
    end

    def extract_alt_titles(md_titles)
      return [] if md_titles.nil?

      # md_titles can be a hash of locale => {title: ...} or an array
      case md_titles
      when Hash
        md_titles.values.filter_map { |v| v.is_a?(Hash) ? v["title"] : v }
      when Array
        md_titles.filter_map { |t| t.is_a?(Hash) ? t["title"] : t }
      else
        []
      end
    end

    def build_chapter_title(number, volume, title)
      parts = []
      parts << "Vol. #{volume}" if volume.present?
      parts << "Ch. #{number}" if number.present?
      parts << "- #{title}" if title.present?
      parts.join(" ").presence || "Chapter"
    end

    def type_from_country(country)
      case country.to_s.downcase
      when "jp"
        "manga"
      when "kr"
        "manhwa"
      when "cn"
        "manhua"
      else
        "manga"
      end
    end

    def browse_popular(page: 1, limit: 20)
      # Comick /api/comics/top accepts days param (7, 30, 90)
      days = case page
      when 1 then 7
      when 2 then 30
      else 90
      end

      response = http.get("/api/comics/top", params: { days: days, type: "follow" })
      payload = parse_json_response(response, endpoint: "/api/comics/top")

      results = payload.is_a?(Hash) ? payload.fetch("data", []) : payload
      results.first(limit).map do |item|
        browse_result_from(item)
      end
    end

    def browse_latest(page: 1, limit: 20)
      response = http.get("/api/chapters/latest", params: { order: "new", page: page })
      payload = parse_json_response(response, endpoint: "/api/chapters/latest")

      results = payload.is_a?(Hash) ? payload.fetch("data", []) : payload
      results.first(limit).map do |item|
        browse_result_from(item)
      end
    end

    def browse_search(sort: "title", page: 1, limit: 20)
      response = http.get("/api/search", params: {
        type: "comic",
        order_by: sort,
        order_direction: "asc",
        page: page,
        limit: limit
      })
      payload = parse_json_response(response, endpoint: "/api/search")

      results = payload.is_a?(Hash) ? payload.fetch("data", []) : payload
      results.map do |item|
        browse_result_from(item)
      end
    end

    def browse_result_from(item)
      ResultTypes::BrowseResult.new(
        id: item["slug"],
        title: item["title"],
        url: comic_url(item["slug"]),
        cover_url: item["default_thumbnail"],
        language: nil,
        author: nil,
        status: nil,
        last_updated: nil,
        chapter_count: nil,
        description: nil
      )
    end

    def parse_json_response(response, endpoint:)
      body = response.body.to_s
      content_type = response.headers["content-type"].to_s

      if response.status.to_i == 403 && html_response?(body, content_type) && body.match?(/just a moment/i)
        raise Scrapers::Errors::RateLimitError, "Comick blocked this request with an anti-bot challenge"
      end

      unless response.status.to_i.between?(200, 299)
        raise Scrapers::Errors::SourceUnavailableError, "Comick API returned HTTP #{response.status} for #{endpoint}"
      end

      if html_response?(body, content_type)
        raise Scrapers::Errors::SourceUnavailableError, "Comick returned HTML instead of JSON for #{endpoint}"
      end

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise Scrapers::Errors::SourceUnavailableError, "Comick returned invalid JSON for #{endpoint}: #{e.message}"
    end

    def html_response?(body, content_type)
      content_type.include?("text/html") || body.lstrip.start_with?("<!DOCTYPE html", "<html")
    end
  end
  end
end
