# frozen_string_literal: true

require "nokogiri"

# Toonily adapter (toonily.me)
# Manhwa/webtoon reading site with custom platform (not WordPress/Madara).
#
# Domain history: toonily.net (shut down ~2025), toonily.com (shut down ~2025),
# toonily.me (current as of 2026).
#
# Endpoints:
#   Search (autocomplete API): GET /api/manga/search?q={query} → HTML fragment
#   Browse (AZ list):          GET /az-list?page={n}&sort={views|latest|az}
#   Series details:            GET /{slug}
#   Chapter pages:             GET /{slug}/{chapter-slug}
#
# Chapter list is inline HTML on the series page (<ul class="chapter-list">).
# Page images use data-src with CDN URLs (s{n}.toonilycdnv2.xyz).
module Scrapers
  module Toonily
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://toonily.me"

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    # Browse via AZ list page. Supports pagination.
    # @param sort [String] "latest" or "popular"
    # @param page [Integer] 1-indexed page number
    # @param limit [Integer] ignored (server controls page size)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20)
      sort_param = sort.to_s.downcase == "popular" ? "views" : "latest"
      response = http.get("#{base_url}/az-list", params: { page: page, sort: sort_param })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_book_items(doc)
    rescue StandardError => e
      Rails.logger.error "[Toonily] Browse error: #{e.message}"
      []
    end

    # Search using the autocomplete API which returns HTML fragments.
    # @param query [String]
    # @return [Array<ResultTypes::SearchResult>]
    def search(query)
      response = http.get("#{base_url}/api/manga/search", params: { q: query })
      return [] unless response.status == 200
      return [] if response.body.blank?

      doc = Nokogiri::HTML.fragment(response.body)

      doc.css(".novel__item").map do |item|
        link = item.at_css(".novel__item-meta .name h3 a")
        next unless link

        href = link["href"]
        title = link["title"] || link.text.strip
        img = item.at_css(".novel__item-icon img")
        cover_url = normalize_image_url(img&.[]("src") || img&.[]("data-src"))

        ResultTypes::SearchResult.new(
          id: href.delete_prefix("/"),
          title: title,
          url: "#{base_url}#{href}",
          cover_url: cover_url,
          author: nil
        )
      end.compact
    rescue StandardError => e
      Rails.logger.error "[Toonily] Search error: #{e.message}"
      []
    end

    # Fetch series details from the series page.
    # @param id_or_url [String] slug or full URL
    # @return [ResultTypes::Series, nil]
    def series(id_or_url)
      url = normalize_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      title = doc.at_css(".detail h1")&.text&.strip
      return nil unless title

      alt_title_el = doc.at_css(".detail .name h2")
      alt_titles = if alt_title_el
        alt_title_el.text.split(/\s*;\s*/).map(&:strip).reject(&:empty?)
      else
        []
      end

      cover_img = doc.at_css(".cover img")
      cover_url = normalize_image_url(cover_img&.[]("data-src") || cover_img&.[]("src"))

      description = doc.at_css(".summary .content")&.text&.strip

      author = extract_meta_value(doc, "Authors") || extract_meta_value(doc, "Author")
      status_text = extract_meta_value(doc, "Status")

      ResultTypes::Series.new(
        id: extract_slug(url),
        title: title,
        alt_titles: alt_titles,
        description: description,
        author: author,
        artist: nil,
        status: normalize_status(status_text),
        tags: [],
        series_type: "manhwa",
        cover_url: cover_url,
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[Toonily] Series error: #{e.message}"
      nil
    end

    # Fetch chapter list from the series page.
    # @param series_url [String] series URL or slug
    # @return [Array<ResultTypes::Chapter>]
    def chapters(series_url)
      url = normalize_url(series_url)
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      doc.css("#chapter-list li a").map do |link|
        href = link["href"]
        next unless href

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        title_el = link.at_css(".chapter-title")
        chapter_text = title_el&.text&.strip || ""

        date_el = link.at_css(".chapter-update")
        published_at = parse_date(date_el&.text&.strip)

        number = extract_chapter_number(href, chapter_text)

        ResultTypes::Chapter.new(
          id: href.split("/").last,
          title: chapter_text.presence,
          number: number || "0",
          volume: nil,
          language: "en",
          group: "Toonily",
          published_at: published_at,
          url: full_url
        )
      end.compact.sort_by { |ch| ch.number.to_f }
    rescue StandardError => e
      Rails.logger.error "[Toonily] Chapters error: #{e.message}"
      []
    end

    # Fetch page images from a chapter page.
    # @param chapter_url [String] chapter URL
    # @return [Array<ResultTypes::Page>]
    def pages(chapter_url)
      response = http.get(chapter_url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      images = []

      doc.css(".chapter-image img").each do |img|
        src = img["data-src"] || img["src"]
        next unless src
        next unless src.include?("toonilycdn")

        images << ResultTypes::Page.new(
          index: images.size,
          url: normalize_image_url(src),
          mime_type: guess_mime_type(src)
        )
      end

      images
    rescue StandardError => e
      Rails.logger.error "[Toonily] Pages error: #{e.message}"
      []
    end

    private

    def base_url
      @config["base_url"] || BASE_URL
    end

    def normalize_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      else
        slug = id_or_url.delete_prefix("/")
        "#{base_url}/#{slug}"
      end
    end

    def extract_slug(url)
      URI(url).path.delete_prefix("/").split("/").first
    end

    # Normalize protocol-relative and relative image URLs.
    def normalize_image_url(url)
      return nil if url.nil? || url.empty?
      return nil if url.include?("x.gif") || url.include?("loading.svg")

      if url.start_with?("//")
        "https:#{url}"
      elsif url.start_with?("/")
        "#{base_url}#{url}"
      else
        url
      end
    end

    # Extract metadata value from the .meta section.
    # Looks for <p><strong>Label :</strong> ... <span>Value</span></p>
    def extract_meta_value(doc, label)
      doc.css(".meta p").each do |p|
        strong = p.at_css("strong")
        next unless strong&.text&.include?(label)

        span = p.at_css("span")
        return span.text.strip if span
      end
      nil
    end

    # Extract chapter number from URL or title text.
    def extract_chapter_number(href, text)
      # URL pattern: /series-slug/chapter-123 or /series-slug/chapter-12-5
      match = href.match(/chapter-(\d+(?:-\d+)?)/i)
      if match
        return match[1].tr("-", ".")
      end

      # Side story pattern: /series-slug/side-story-21-the-end
      match = href.match(/side-story-(\d+)/i)
      return "side-#{match[1]}" if match

      # Text pattern: "Chapter 123" or "Chapter 12.5"
      match = text.match(/chapter\s*(\d+(?:\.\d+)?)/i)
      return match[1] if match

      nil
    end

    # Parse date strings like "Jun 20, 2023", "a year ago", "3 years ago"
    def parse_date(text)
      return nil if text.blank?

      if text.match?(/\d+ \w+ ago|a \w+ ago/i)
        nil # Relative dates are imprecise, skip them
      else
        Date.parse(text)
      end
    rescue Date::Error
      nil
    end

    # Parse book-item elements from browse/genre pages.
    def parse_book_items(doc)
      doc.css(".book-item").map do |item|
        link = item.at_css(".book-detailed-item .thumb a") || item.at_css("a")
        next unless link

        href = link["href"]
        title = link["title"] || item.at_css(".meta .title h3 a")&.text&.strip
        next unless title && href

        img = item.at_css("img")
        cover_url = normalize_image_url(img&.[]("data-src") || img&.[]("src"))

        latest_chapter = item.at_css(".latest-chapter")&.text&.strip

        ResultTypes::BrowseResult.new(
          id: href.delete_prefix("/"),
          title: title,
          url: "#{base_url}#{href}",
          cover_url: cover_url,
          language: "en",
          author: nil,
          status: nil,
          last_updated: nil,
          chapter_count: extract_chapter_count(latest_chapter),
          description: nil
        )
      end.compact
    end

    # Extract chapter count from latest chapter text like "Chapter 160"
    def extract_chapter_count(text)
      return nil if text.blank?
      match = text.match(/chapter\s*(\d+)/i)
      match ? match[1].to_i : nil
    end

    def guess_mime_type(url)
      case url.downcase
      when /\.png/ then "image/png"
      when /\.gif/ then "image/gif"
      when /\.webp/ then "image/webp"
      else "image/jpeg"
      end
    end
  end
  end
end
