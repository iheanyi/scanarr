# frozen_string_literal: true

require "json"
require "nokogiri"
require "cgi"

# MangaFire adapter (mangafire.to)
# Reference: https://github.com/keiyoushi/extensions-source (mangafire extension)
#
# MangaFire is a large manga aggregator with 52,000+ titles supporting
# multiple languages. Uses a hybrid approach:
# - HTML scraping for search/filter results and series details
# - AJAX endpoints for chapter lists and page images
#
# URL patterns:
#   Series: /manga/{slug}.{id}  (e.g., /manga/one-piecee.dkw)
#   Chapter: /read/{slug}.{id}/{lang}/chapter-{number}
#   AJAX chapters: /ajax/manga/{id}/chapter/{lang}
#   AJAX pages: /ajax/read/{slug}.{id}/en/chapter-{number}
#
# Browse supports: recently_updated, most_viewed, trending, title_az
# Search requires a VRF token (WebView-based in Tachiyomi), so we use
# the filter page without keyword for browse and the series page for details.
module Scrapers
  module MangaFire
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://mangafire.to"

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular alphabetical]
    end

    # Browse manga via the /filter endpoint (no keyword = no VRF needed)
    # @param sort [String] "latest", "popular", or "alphabetical"
    # @param page [Integer] Page number (1-indexed)
    # @param limit [Integer] Ignored (site uses fixed page size)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = filters
      sort_param = sort_value(sort)

      response = http.get("#{base_url}/filter", params: {
        "sort" => sort_param,
        "language[]" => "en",
        "page" => page.to_s
      })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_card_list(doc).map do |result|
        ResultTypes::BrowseResult.new(
          id: result.id,
          title: result.title,
          url: result.url,
          cover_url: result.cover_url,
          language: "en",
          author: result.author,
          status: nil,
          last_updated: nil,
          chapter_count: nil,
          description: nil
        )
      end
    rescue StandardError => e
      Rails.logger.error "[MangaFire] Browse error: #{e.message}"
      []
    end

    # Search for manga by keyword
    # MangaFire search requires a VRF token for keyword searches on /filter.
    # We use the /filter endpoint with keyword param. If VRF is needed and
    # we don't have it, results may be empty.
    # @param query [String] Search term
    # @return [Array<ResultTypes::SearchResult>]
    def search(query, filters: {})
      _ = filters
      encoded_query = query.to_s.strip
      return [] if encoded_query.empty?

      response = http.get("#{base_url}/filter", params: {
        "keyword" => encoded_query,
        "language[]" => "en",
        "sort" => "most_relevance",
        "page" => "1"
      })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_card_list(doc)
    rescue StandardError => e
      Rails.logger.error "[MangaFire] Search error: #{e.message}"
      []
    end

    # Fetch series details from the manga page
    # @param id_or_url [String] Series slug (e.g., "one-piecee.dkw"), path, or full URL
    # @return [ResultTypes::Series, nil]
    def series(id_or_url)
      url = normalize_series_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      title = doc.at_css("h1")&.text&.strip
      return nil unless title.present?

      # Cover image from poster section
      cover_url = doc.at_css(".poster img")&.[]("src")
      cover_url ||= doc.css("img").find { |img|
        src = img["src"]
        src && src.include?("static.mfcdn.cc") && !src.include?("avatar")
      }&.[]("src")

      # Alternative titles from h6 element
      alt_titles = []
      alt_el = doc.at_css("h6")
      if alt_el
        alt_titles = alt_el.text.split(";").map(&:strip).reject(&:empty?)
      end

      # Status from info section
      status = extract_meta_value(doc, "Status") || extract_status_from_text(doc)

      # Author from author link
      author = doc.at_css("a[href*='/author/']")&.text&.strip
      author ||= extract_meta_value(doc, "Author")

      # Type (Manga, Manhwa, Manhua)
      series_type = extract_meta_value(doc, "Type")

      # Genres from genre links
      genres = doc.css("a[href*='/genre/']").map { |a| a.text.strip }.reject(&:empty?).uniq

      # Description from synopsis section
      description = doc.at_css("#synopsis .modal-content")&.text&.strip
      description ||= doc.at_css("#synopsis")&.text&.strip
      description ||= doc.css("p").find { |p|
        text = p.text.strip
        text.length > 50 && !text.include?("MangaFire")
      }&.text&.strip

      ResultTypes::Series.new(
        id: extract_manga_id(url),
        title: title,
        alt_titles: alt_titles,
        description: description,
        author: author,
        artist: extract_meta_value(doc, "Artist") || author,
        status: normalize_status(status),
        tags: genres,
        series_type: (series_type || detect_type_from_genres(genres)).to_s.downcase.presence || "manga",
        cover_url: cover_url,
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[MangaFire] Series error: #{e.message}"
      nil
    end

    # Fetch chapters for a series
    # First tries parsing from the series page HTML, then falls back to AJAX endpoint
    # @param series_url [String] Series URL, slug, or ID
    # @return [Array<ResultTypes::Chapter>]
    def chapters(series_url)
      url = normalize_series_url(series_url)
      manga_id = extract_manga_id(url)

      # Try AJAX endpoint first (returns HTML fragment with all chapters)
      ajax_url = "#{base_url}/ajax/manga/#{manga_id}/chapter/en"
      ajax_response = http.get(ajax_url)

      if ajax_response.status == 200
        chapters = parse_ajax_chapters(ajax_response.body, url)
        return chapters unless chapters.empty?
      end

      # Fallback: parse chapters from the series page HTML
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_html_chapters(doc, url)
    rescue StandardError => e
      Rails.logger.error "[MangaFire] Chapters error: #{e.message}"
      []
    end

    # Fetch page images for a chapter
    # Uses AJAX endpoint to get image data
    # @param chapter_url [String] Chapter URL
    # @return [Array<ResultTypes::Page>]
    def pages(chapter_url)
      url = chapter_url.start_with?("http") ? chapter_url : "#{base_url}#{chapter_url}"

      # Try AJAX endpoint for page images
      # Convert /read/slug.id/en/chapter-N to /ajax/read/slug.id/en/chapter-N
      ajax_url = url.sub("#{base_url}/read/", "#{base_url}/ajax/read/")
      ajax_response = http.get(ajax_url)

      if ajax_response.status == 200
        pages = parse_ajax_pages(ajax_response.body)
        return pages unless pages.empty?
      end

      # Fallback: try loading the chapter page directly and extracting images
      response = http.get(url)
      return [] unless response.status == 200

      parse_html_pages(response.body)
    rescue StandardError => e
      Rails.logger.error "[MangaFire] Pages error: #{e.message}"
      []
    end

    private

    # Map sort option to MangaFire's sort parameter
    def sort_value(sort)
      case sort.to_s.downcase
      when "popular" then "most_viewed"
      when "alphabetical" then "title_az"
      else "recently_updated"
      end
    end

    # Parse manga cards from filter/browse pages
    # Card structure:
    #   .unit .inner > .info > a (title link)
    #   .unit .inner > img (cover)
    # or generic card pattern:
    #   a[href*="/manga/"] with img and title text
    def parse_card_list(doc)
      results = []
      seen_ids = Set.new

      # Primary selector: MangaFire card structure
      doc.css(".original .unit .inner, .unit .inner, .item").each do |card|
        result = parse_card_element(card)
        next unless result
        next if seen_ids.include?(result.id)

        seen_ids << result.id
        results << result
      end

      # Fallback: look for manga links directly
      if results.empty?
        doc.css("a[href*='/manga/']").each do |link|
          href = link["href"]
          next unless href&.match?(%r{/manga/[^/]+\.\w+})

          manga_id = extract_manga_id(href)
          next if seen_ids.include?(manga_id)

          title = link.text.strip
          title = link["title"]&.strip if title.empty?
          next unless title.present?

          seen_ids << manga_id
          img = link.css("img").first || link.parent&.css("img")&.first

          results << ResultTypes::SearchResult.new(
            id: manga_id,
            title: title,
            url: normalize_manga_url(href),
            cover_url: img&.[]("src") || img&.[]("data-src"),
            author: nil
          )
        end
      end

      results
    end

    # Parse a single card element into a SearchResult
    def parse_card_element(card)
      # Find the title link
      link = card.at_css(".info > a") ||
             card.at_css("a[href*='/manga/']") ||
             card.at_css("h3 a")
      return nil unless link

      href = link["href"]
      return nil unless href&.match?(%r{/manga/})

      title = link.attr("title")&.strip
      title = link.text.strip if title.blank?
      return nil unless title.present?

      # Cover image
      img = card.at_css("img")
      cover_url = img&.[]("src") || img&.[]("data-src")

      manga_id = extract_manga_id(href)
      return nil unless manga_id.present?

      ResultTypes::SearchResult.new(
        id: manga_id,
        title: title,
        url: normalize_manga_url(href),
        cover_url: cover_url,
        author: nil
      )
    end

    # Parse chapters from AJAX response
    # The AJAX endpoint returns JSON with a "result" key containing HTML
    def parse_ajax_chapters(body, series_url)
      data = JSON.parse(body)
      html = data["result"]
      return [] unless html.present?

      doc = Nokogiri::HTML.fragment(html)
      chapters = []

      doc.css("li").each do |li|
        link = li.at_css("a")
        next unless link

        href = link["href"]
        next unless href

        number = li.attr("data-number")
        number ||= extract_chapter_number(href) || extract_chapter_number(link.text)

        title_span = li.at_css("span")
        title_text = title_span&.text&.strip

        # Parse chapter title: "Chap 1173: Warrior Generation" -> "Warrior Generation"
        chapter_title = nil
        if title_text
          match = title_text.match(/^Chap\s+[\d.]+:\s*(.+)/i)
          chapter_title = match ? match[1].strip : nil
        end

        date_span = li.css("span").last
        published_at = parse_date(date_span&.text&.strip)

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        chapters << ResultTypes::Chapter.new(
          id: extract_chapter_id(href),
          title: chapter_title,
          number: number || "0",
          volume: nil,
          language: "en",
          group: "MangaFire",
          published_at: published_at,
          url: full_url
        )
      end

      chapters.uniq { |ch| ch.number }.sort_by { |ch| ch.number.to_f }
    rescue JSON::ParserError
      []
    end

    # Parse chapters from the series page HTML
    def parse_html_chapters(doc, series_url)
      chapters = []

      doc.css("a[href*='/read/'][href*='/chapter-']").each do |link|
        href = link["href"]
        next unless href

        chapter_num = extract_chapter_number(href)
        next unless chapter_num

        title_text = link.text.strip
        # Parse title from "Chapter 1173: Warrior Generation Jan 30, 2026"
        chapter_title = nil
        match = title_text.match(/Chapter\s+[\d.]+[:\s]*(.+?)(?:\d+\s+(?:hours?|days?|weeks?|months?)\s+ago|\w+\s+\d+,\s+\d{4}|$)/i)
        chapter_title = match[1].strip.presence if match

        published_at = parse_date_from_text(title_text)

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        chapters << ResultTypes::Chapter.new(
          id: extract_chapter_id(href),
          title: chapter_title,
          number: chapter_num,
          volume: nil,
          language: "en",
          group: "MangaFire",
          published_at: published_at,
          url: full_url
        )
      end

      chapters.uniq { |ch| ch.number }.sort_by { |ch| ch.number.to_f }
    end

    # Parse page images from AJAX response
    # Returns JSON: { "result": { "images": [[url, width, offset], ...] } }
    def parse_ajax_pages(body)
      data = JSON.parse(body)
      images = data.dig("result", "images") || data.dig("result", "pages")
      return [] unless images.is_a?(Array)

      images.each_with_index.map do |img_data, idx|
        url = img_data.is_a?(Array) ? img_data[0] : img_data.to_s
        next unless url.present?

        ResultTypes::Page.new(
          index: idx,
          url: url,
          mime_type: guess_mime_type(url)
        )
      end.compact
    rescue JSON::ParserError
      []
    end

    # Parse page images from HTML (fallback)
    def parse_html_pages(body)
      doc = Nokogiri::HTML(body)
      images = []

      # Look for reader images
      doc.css("img[src*='mfcdn'], img[data-src*='mfcdn']").each_with_index do |img, idx|
        src = img["src"] || img["data-src"]
        next unless src && looks_like_page_url?(src)

        images << ResultTypes::Page.new(
          index: idx,
          url: src,
          mime_type: guess_mime_type(src)
        )
      end

      # Fallback: extract from JavaScript
      if images.empty?
        js_images = extract_js_images(body)
        js_images.each_with_index do |url, idx|
          images << ResultTypes::Page.new(
            index: idx,
            url: url,
            mime_type: guess_mime_type(url)
          )
        end
      end

      images
    end

    # Extract image URLs from JavaScript in the page
    def extract_js_images(body)
      # Try matching JSON image arrays
      match = body.match(/"images"\s*:\s*(\[\[.*?\]\])/m)
      if match
        begin
          data = JSON.parse(match[1])
          return data.map { |entry| entry.is_a?(Array) ? entry[0] : entry.to_s }.compact
        rescue JSON::ParserError
          # Fall through
        end
      end

      # Try plain URL arrays
      match = body.match(/"images"\s*:\s*(\["https?:.*?\])/m)
      if match
        begin
          return JSON.parse(match[1])
        rescue JSON::ParserError
          # Fall through
        end
      end

      []
    end

    # Extract manga ID from URL
    # /manga/one-piecee.dkw -> dkw
    # /manga/solo-leveling.38y -> 38y
    def extract_manga_id(url_or_path)
      return nil unless url_or_path
      match = url_or_path.match(%r{/(?:manga|read)/([^/]+\.(\w+))})
      match ? match[1] : url_or_path.split("/").last
    end

    # Extract the short ID from a manga slug (the part after the dot)
    def extract_short_id(url_or_path)
      return nil unless url_or_path
      match = url_or_path.match(%r{/(?:manga|read)/[^/]+\.(\w+)})
      match ? match[1] : nil
    end

    # Extract chapter ID from URL
    # /read/one-piecee.dkw/en/chapter-1173 -> chapter-1173
    def extract_chapter_id(url_or_path)
      return nil unless url_or_path
      match = url_or_path.match(%r{/(chapter-[\d.]+)})
      match ? match[1] : url_or_path.split("/").last
    end

    # Extract chapter number from text or URL
    def extract_chapter_number(text)
      return nil unless text

      # Match /chapter-123 or /chapter-123.5
      match = text.match(%r{chapter[- ]?(\d+(?:\.\d+)?)}i)
      return match[1] if match

      # Match "Chap 123" or "Ch.123"
      match = text.match(/ch(?:ap)?[.\s]*(\d+(?:\.\d+)?)/i)
      return match[1] if match

      nil
    end

    # Normalize a series URL from various input formats
    def normalize_series_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.start_with?("/")
        "#{base_url}#{id_or_url}"
      else
        "#{base_url}/manga/#{id_or_url}"
      end
    end

    # Normalize a manga href to full URL
    def normalize_manga_url(href)
      return href if href.start_with?("http")
      "#{base_url}#{href}"
    end

    # Extract metadata value from the page
    def extract_meta_value(doc, label)
      # Look for "Label: Value" patterns in spans or divs
      doc.css("span, div, p").each do |el|
        text = el.text.strip
        match = text.match(/\b#{Regexp.escape(label)}\s*[:]\s*(.+)/i)
        return match[1].strip if match
      end
      nil
    end

    # Extract status from known text patterns
    def extract_status_from_text(doc)
      %w[Releasing Completed On_hiatus Discontinued].each do |status|
        return status if doc.text.include?(status)
      end
      nil
    end

    # Detect series type from genres
    def detect_type_from_genres(genres)
      genres_lower = (genres || []).map(&:downcase)
      return "Manhwa" if genres_lower.any? { |g| g.include?("manhwa") }
      return "Manhua" if genres_lower.any? { |g| g.include?("manhua") }
      "Manga"
    end

    # Parse date strings like "Jan 30, 2026" or "2 hours ago"
    def parse_date(text)
      return nil unless text.present?

      # Try standard date format
      begin
        return DateTime.parse(text)
      rescue Date::Error, ArgumentError
        # Fall through to relative parsing
      end

      # Relative dates: "2 hours ago", "3 days ago"
      parse_relative_date(text)
    end

    # Extract and parse date from chapter text
    def parse_date_from_text(text)
      return nil unless text

      # Match "Jan 30, 2026" format
      match = text.match(/(\w{3}\s+\d{1,2},\s+\d{4})/)
      return parse_date(match[1]) if match

      # Match relative dates
      match = text.match(/(\d+\s+(?:hours?|days?|weeks?|months?)\s+ago)/i)
      return parse_relative_date(match[1]) if match

      nil
    end

    # Parse relative date strings
    def parse_relative_date(text)
      return nil unless text

      match = text.match(/(\d+)\s+(hour|day|week|month)s?\s+ago/i)
      return nil unless match

      amount = match[1].to_i
      unit = match[2].downcase

      case unit
      when "hour" then DateTime.now - Rational(amount, 24)
      when "day" then DateTime.now - amount
      when "week" then DateTime.now - (amount * 7)
      when "month" then DateTime.now - (amount * 30)
      else DateTime.now
      end
    end

    def looks_like_page_url?(url)
      return false if url.nil?
      return false if url.include?("logo")
      return false if url.include?("avatar")
      return false if url.include?("icon")
      return false if url.include?("favicon")

      url.match?(/\.(jpg|jpeg|png|webp|gif)/i) || url.include?("mfcdn")
    end

    def guess_mime_type(url)
      case url.to_s.downcase
      when /\.png/ then "image/png"
      when /\.gif/ then "image/gif"
      when /\.webp/ then "image/webp"
      else "image/jpeg"
      end
    end
  end
  end
end
