# frozen_string_literal: true

require "nokogiri"

# ManhuaPlus adapter (manhuaplus.com / manhuaplus.top)
# Reference: https://github.com/keiyoushi/extensions-source (Madara multisrc)
#
# ManhuaPlus is a WordPress/Madara-based manhua aggregator.
# Domain has migrated from manhuaplus.com to manhuaplus.top.
# Uses standard Madara theme selectors for search, series, chapters, and pages.
#
# Search: GET /?s={query}&post_type=wp-manga
# Series: GET /manga/{slug}/
# Chapters: AJAX POST to /manga/{slug}/ajax/chapters/ or inline li.wp-manga-chapter
# Pages: GET /manga/{slug}/{chapter-slug}/ with images in div.page-break img
module Scrapers
  module ManhuaPlus
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://manhuaplus.com"

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    # Browse latest or popular manga via AJAX endpoint
    # @param sort [String] "latest" or "popular"
    # @param page [Integer] Page number (1-indexed)
    # @param limit [Integer] Ignored (uses site default)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = filters
      body = {
        "action" => "madara_load_more",
        "page" => (page - 1).to_s,
        "template" => "madara-core/content/content-archive",
        "vars[orderby]" => sort == "popular" ? "meta_value_num" : "latest",
        "vars[post_type]" => "wp-manga",
        "vars[post_status]" => "publish"
      }
      body["vars[meta_key]"] = "_wp_manga_views" if sort == "popular"

      response = http.post("#{base_url}/wp-admin/admin-ajax.php", body: body, headers: xhr_headers)

      if response.status != 200 || response.body.strip.empty?
        return browse_html_fallback(sort, page)
      end

      doc = Nokogiri::HTML(response.body)
      parse_browse_results(doc)
    rescue StandardError => e
      Rails.logger.error "[ManhuaPlus] Browse error: #{e.message}"
      []
    end

    # Search for manga by title
    # @param query [String] Search term
    # @return [Array<ResultTypes::SearchResult>]
    def search(query, filters: {})
      _ = filters
      response = http.get(base_url, params: { "s" => query, "post_type" => "wp-manga" })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_search_results(doc)
    rescue StandardError => e
      Rails.logger.error "[ManhuaPlus] Search error: #{e.message}"
      []
    end

    # Fetch series details
    # @param id_or_url [String] Series slug or full URL
    # @return [ResultTypes::Series, nil]
    def series(id_or_url)
      url = normalize_series_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      title = doc.at_css("div.post-title h3, div.post-title h1, #manga-title h1")&.text&.strip
      return nil unless title.present?

      ResultTypes::Series.new(
        id: extract_slug(url),
        title: title,
        alt_titles: extract_alt_titles(doc),
        description: extract_description(doc),
        author: extract_meta_value(doc, "Author"),
        artist: extract_meta_value(doc, "Artist"),
        status: normalize_status(extract_status(doc)),
        tags: extract_genres(doc),
        series_type: detect_series_type(extract_genres(doc)),
        cover_url: extract_cover(doc),
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[ManhuaPlus] Series error: #{e.message}"
      nil
    end

    # Fetch chapter list for a series
    # Tries AJAX endpoint first, falls back to inline chapters
    # @param series_url [String] Series URL or slug
    # @return [Array<ResultTypes::Chapter>]
    def chapters(series_url)
      url = normalize_series_url(series_url)

      # Try AJAX chapter loading first (Madara new endpoint)
      ajax_url = url.chomp("/") + "/ajax/chapters/"
      ajax_response = http.post(ajax_url, headers: xhr_headers)

      if ajax_response.status == 200 && ajax_response.body.present?
        doc = Nokogiri::HTML(ajax_response.body)
        result = parse_chapters(doc)
        return result if result.any?
      end

      # Fallback: parse inline chapters from series page
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_chapters(doc)
    rescue StandardError => e
      Rails.logger.error "[ManhuaPlus] Chapters error: #{e.message}"
      []
    end

    # Fetch page image URLs for a chapter
    # @param chapter_url [String] Chapter URL
    # @return [Array<ResultTypes::Page>]
    def pages(chapter_url)
      url = chapter_url.start_with?("http") ? chapter_url : "#{base_url}#{chapter_url}"
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_pages(doc)
    rescue StandardError => e
      Rails.logger.error "[ManhuaPlus] Pages error: #{e.message}"
      []
    end

    private

    def base_url
      config["base_url"] || BASE_URL
    end

    def xhr_headers
      { "X-Requested-With" => "XMLHttpRequest" }
    end

    # Fallback browse via HTML page scraping
    def browse_html_fallback(sort, page)
      path = case sort
      when "popular"
               "/manga/?m_orderby=views"
      else
               "/manga/?m_orderby=latest"
      end
      path += "&page=#{page}" if page > 1

      response = http.get("#{base_url}#{path}")
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_browse_results(doc)
    rescue StandardError => e
      Rails.logger.error "[ManhuaPlus] Browse HTML fallback error: #{e.message}"
      []
    end

    # Parse browse results from Madara page-item-detail cards
    def parse_browse_results(doc)
      doc.css("div.page-item-detail").map do |card|
        link = card.at_css("h3.h5 a, h5 a, div.post-title a")
        next unless link

        href = link["href"]
        title = link.text.strip
        next unless title.present? && href.present?

        img = card.at_css("img")
        cover_url = img&.[]("data-src") || img&.[]("src")

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::BrowseResult.new(
          id: extract_slug(href),
          title: title,
          url: full_url,
          cover_url: cover_url,
          language: "en",
          author: nil,
          status: nil,
          last_updated: nil,
          chapter_count: nil,
          description: nil
        )
      end.compact
    end

    # Parse search results from Madara search page
    def parse_search_results(doc)
      results = []

      doc.css("div.c-tabs-item__content, div.row.c-tabs-item__content").each do |card|
        link = card.at_css("div.post-title a, h3 a, h4 a")
        next unless link

        href = link["href"]
        title = link.text.strip
        next unless title.present? && href.present?

        img = card.at_css("img")
        cover_url = img&.[]("data-src") || img&.[]("src")

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        results << ResultTypes::SearchResult.new(
          id: extract_slug(href),
          title: title,
          url: full_url,
          cover_url: cover_url,
          author: card.at_css("div.mg_author span.summary-content a, span.author-content a")&.text&.strip
        )
      end

      results
    end

    # Extract alt titles from Madara series page
    def extract_alt_titles(doc)
      alt_el = doc.at_css("div.summary-content .alternative-title, div.post-content_item:contains('Alternative') .summary-content")
      return [] unless alt_el

      alt_el.text.strip.split(/[;,]/).map(&:strip).reject(&:empty?)
    end

    # Extract description from Madara series page
    def extract_description(doc)
      desc_el = doc.at_css("div.description-summary div.summary__content, div.summary__content")
      return nil unless desc_el

      desc_el.css("a, span.show-more, p.show-more").each(&:remove)
      text = desc_el.text.strip.gsub(/\s+/, " ")
      text.presence
    end

    # Extract author/artist from Madara meta fields
    def extract_meta_value(doc, label)
      case label
      when "Author"
        doc.at_css("div.author-content a, div.manga-authors a")&.text&.strip
      when "Artist"
        doc.at_css("div.artist-content a")&.text&.strip
      end
    end

    # Extract status from Madara series page
    def extract_status(doc)
      status_el = doc.at_css("div.post-status div.summary-content, div.summary-heading:contains('Status') + div.summary-content")
      status_el&.text&.strip
    end

    # Extract genres from Madara series page
    def extract_genres(doc)
      doc.css("div.genres-content a").map { |a| a.text.strip }.reject(&:empty?).uniq
    end

    # Extract cover image from Madara series page
    def extract_cover(doc)
      img = doc.at_css("div.summary_image img")
      return nil unless img

      img["data-src"] || img["src"]
    end

    # Parse chapters from Madara series page or AJAX response
    def parse_chapters(doc)
      doc.css("li.wp-manga-chapter").map do |li|
        link = li.at_css("a")
        next unless link

        href = link["href"]
        chapter_text = link.text.strip
        next unless href.present?

        chapter_num = extract_chapter_number(chapter_text)

        date_el = li.at_css("span.chapter-release-date, span.chapter-release-date i")
        published_at = parse_madara_date(date_el&.text&.strip)

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::Chapter.new(
          id: extract_chapter_slug(href),
          title: extract_chapter_title(chapter_text),
          number: chapter_num || "0",
          volume: nil,
          language: "en",
          group: "ManhuaPlus",
          published_at: published_at,
          url: full_url
        )
      end.compact.uniq { |ch| ch.number }.sort_by { |ch| ch.number.to_f }
    end

    # Parse page images from Madara chapter reader
    def parse_pages(doc)
      images = []

      doc.css("div.page-break img, li.blocks-gallery-item img, .reading-content img").each_with_index do |img, idx|
        src = img["data-src"]&.strip || img["data-lazy-src"]&.strip || img["src"]&.strip
        next unless src.present?
        next unless looks_like_page_url?(src)

        images << ResultTypes::Page.new(
          index: idx,
          url: src,
          mime_type: guess_mime_type(src)
        )
      end

      images
    end

    # Extract slug from a Madara manga URL
    def extract_slug(url)
      match = url.to_s.match(%r{/manga/([^/?]+)})
      match ? match[1].chomp("/") : url.to_s.split("/").reject(&:empty?).last
    end

    # Extract chapter slug from URL
    def extract_chapter_slug(url)
      parts = url.to_s.split("/").reject(&:empty?)
      parts.last || url
    end

    # Normalize series URL from various input formats
    def normalize_series_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.start_with?("/")
        "#{base_url}#{id_or_url}"
      else
        "#{base_url}/manga/#{id_or_url}/"
      end
    end

    # Extract chapter number from text
    def extract_chapter_number(text)
      return nil unless text

      match = text.match(/chapter[- ]*(\d+(?:\.\d+)?)/i)
      match&.[](1)
    end

    # Extract chapter title (text after the chapter number)
    def extract_chapter_title(text)
      return nil unless text

      title = text.sub(/chapter[- ]*\d+(?:\.\d+)?[:\s-]*/i, "").strip
      title.presence
    end

    # Parse Madara date formats
    # ManhuaPlus uses "Month DD, YYYY" (e.g., "December 22, 2025") and relative dates
    def parse_madara_date(text)
      return nil unless text.present?

      # Try "Month DD, YYYY" format (with optional ordinal suffixes like "5th")
      cleaned = text.strip.gsub(/(\d+)(st|nd|rd|th)/, '\1')
      Date.strptime(cleaned, "%B %d, %Y").to_time
    rescue Date::Error, ArgumentError
      begin
        # Try MM/dd/yy format
        Date.strptime(text.strip, "%m/%d/%y").to_time
      rescue Date::Error, ArgumentError
        parse_relative_date(text)
      end
    end

    # Parse relative date strings like "3 hours ago", "2 days ago"
    def parse_relative_date(text)
      return nil unless text.present?

      text = text.downcase.strip
      match = text.match(/(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago/)
      return nil unless match

      amount = match[1].to_i
      unit = match[2]

      case unit
      when "second" then Time.current - amount.seconds
      when "minute" then Time.current - amount.minutes
      when "hour" then Time.current - amount.hours
      when "day" then Time.current - amount.days
      when "week" then Time.current - amount.weeks
      when "month" then Time.current - amount.months
      when "year" then Time.current - amount.years
      end
    end

    def looks_like_page_url?(url)
      return false if url.nil?
      return false if url.include?("logo")
      return false if url.include?("avatar")
      return false if url.include?("icon")
      return false if url.include?("favicon")

      url.match?(/\.(jpg|jpeg|png|webp|gif)/i) || url.include?("cdn") || url.include?("wp-content")
    end

    def guess_mime_type(url)
      case url.downcase
      when /\.png/ then "image/png"
      when /\.gif/ then "image/gif"
      when /\.webp/ then "image/webp"
      else "image/jpeg"
      end
    end

    # Detect series type from genre tags
    def detect_series_type(tags)
      tags_lower = (tags || []).map(&:downcase)
      return "manhwa" if tags_lower.any? { |t| t.include?("manhwa") || t.include?("korean") }
      return "manhua" if tags_lower.any? { |t| t.include?("manhua") || t.include?("chinese") }
      "manga"
    end
  end
  end
end
