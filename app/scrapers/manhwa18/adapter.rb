# frozen_string_literal: true

require "nokogiri"

# Manhwa18 adapter (manhwa18.net)
# Adult manhwa/webtoon reading site.
#
# Domain history: manhwa18.com (Cloudflare-blocked API), manhwa18.cc,
# manhwa18.net (current HTML-based, as of 2026).
#
# Endpoints:
#   Search:          GET /tim-kiem?q={query}
#   Browse (list):   GET /manga-list?page={n}&sort={latest|new|most-view}
#   Series details:  GET /manga/{slug}
#   Chapter pages:   GET /manga/{slug}/chapter-{num}-{id}
#
# Chapter list is inline on the series page (ul.list-chapters.at-series).
# Page images use data-src with CDN URLs (cdn.manhwa18.com).
module Manhwa18
  class Adapter < ::BaseAdapter
    BASE_URL = "https://manhwa18.net"

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    # Browse manga list with pagination.
    # @param sort [String] "latest" or "popular"
    # @param page [Integer] 1-indexed page number
    # @param limit [Integer] ignored (server controls page size)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20)
      sort_param = sort.to_s.downcase == "popular" ? "most-view" : "latest"
      response = http.get("#{base_url}/manga-list", params: { page: page, sort: sort_param })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_thumb_items(doc)
    rescue StandardError => e
      Rails.logger.error "[Manhwa18] Browse error: #{e.message}"
      []
    end

    # Search via the /tim-kiem endpoint.
    # @param query [String]
    # @return [Array<ResultTypes::SearchResult>]
    def search(query)
      response = http.get("#{base_url}/tim-kiem", params: { q: query })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      doc.css(".thumb-item-flow").map do |item|
        title_link = item.at_css(".series-title a")
        next unless title_link

        href = title_link["href"]
        title = title_link["title"] || title_link.text.strip
        cover_url = extract_cover_url(item)
        slug = extract_slug_from_url(href)

        next unless title.present? && slug

        ResultTypes::SearchResult.new(
          id: slug,
          title: title,
          url: normalize_full_url(href),
          cover_url: cover_url,
          author: nil
        )
      end.compact
    rescue StandardError => e
      Rails.logger.error "[Manhwa18] Search error: #{e.message}"
      []
    end

    # Fetch series details from the manga page.
    # @param id_or_url [String] slug or full URL
    # @return [ResultTypes::Series, nil]
    def series(id_or_url)
      url = normalize_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      title = doc.at_css(".series-name a")&.text&.strip
      return nil unless title

      cover_url = extract_series_cover(doc)
      description = doc.at_css(".summary-content")&.text&.strip

      alt_titles = []
      alt_el = doc.at_css(".info-item .info-name")&.then do |el|
        el.text.strip.downcase.include?("other name") ? el.parent : nil
      end
      if alt_el
        alt_text = alt_el.at_css(".info-value")&.text&.strip
        alt_titles = alt_text.split(/[;,]/).map(&:strip).reject(&:empty?) if alt_text
      end

      status_text = extract_info_value(doc, "Status")
      genres = doc.css(".series-information a[href*='/genre/'] .badge").map { |g| g.text.strip }

      ResultTypes::Series.new(
        id: extract_slug_from_url(url),
        title: title,
        alt_titles: alt_titles,
        description: description,
        author: nil,
        artist: nil,
        status: normalize_status(status_text),
        tags: genres,
        series_type: "manhwa",
        cover_url: cover_url,
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[Manhwa18] Series error: #{e.message}"
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

      doc.css(".list-chapters.at-series a").map do |link|
        href = link["href"]
        next unless href

        full_url = normalize_full_url(href)
        chapter_title = link.at_css(".chapter-name")&.text&.strip || link["title"]
        time_text = link.at_css(".chapter-time")&.text&.strip
        published_at = parse_date(time_text)

        number = extract_chapter_number(href, chapter_title)

        ResultTypes::Chapter.new(
          id: href.split("/").last,
          title: chapter_title.presence,
          number: number || "0",
          volume: nil,
          language: "en",
          group: "Manhwa18",
          published_at: published_at,
          url: full_url
        )
      end.compact.sort_by { |ch| ch.number.to_f }
    rescue StandardError => e
      Rails.logger.error "[Manhwa18] Chapters error: #{e.message}"
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

      doc.css("#chapter-content img").each do |img|
        src = img["data-src"] || img["src"]
        next unless src
        next unless looks_like_page_url?(src)

        images << ResultTypes::Page.new(
          index: images.size,
          url: src.strip,
          mime_type: guess_mime_type(src)
        )
      end

      images
    rescue StandardError => e
      Rails.logger.error "[Manhwa18] Pages error: #{e.message}"
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
        "#{base_url}/manga/#{slug}"
      end
    end

    def normalize_full_url(href)
      if href.start_with?("http")
        href
      else
        "#{base_url}#{href.start_with?("/") ? "" : "/"}#{href}"
      end
    end

    def extract_slug_from_url(url)
      path = url.is_a?(URI) ? url.path : URI(url).path
      match = path.match(%r{/manga/([^/]+)})
      match ? match[1] : path.split("/").last
    rescue URI::InvalidURIError
      url.split("/").last
    end

    # Extract cover from the series page background-image style.
    def extract_series_cover(doc)
      cover_div = doc.at_css(".series-cover .content.img-in-ratio")
      if cover_div
        bg = cover_div["data-bg"] || cover_div["style"]&.match(/url\(['"]?([^'")\s]+)/)&.[](1)
        return bg if bg
      end

      # Fallback: og:image meta tag
      doc.at_css("meta[property='og:image']")&.[]("content")
    end

    # Extract cover URL from a thumbnail item (search/browse results).
    def extract_cover_url(item)
      cover_div = item.at_css(".content.img-in-ratio")
      if cover_div
        return cover_div["data-bg"] || cover_div["style"]&.match(/url\(['"]?([^'")\s]+)/)&.[](1)
      end

      img = item.at_css("img")
      img&.[]("data-src") || img&.[]("src")
    end

    # Extract an info value from the series-information section.
    def extract_info_value(doc, label)
      doc.css(".series-information .info-item").each do |item|
        name_el = item.at_css(".info-name")
        next unless name_el&.text&.strip&.downcase&.include?(label.downcase)

        value_el = item.at_css(".info-value")
        return value_el.text.strip if value_el
      end
      nil
    end

    # Parse thumb-item-flow elements from browse/search pages.
    def parse_thumb_items(doc)
      doc.css(".thumb-item-flow").map do |item|
        title_link = item.at_css(".series-title a")
        next unless title_link

        href = title_link["href"]
        title = title_link["title"] || title_link.text.strip
        cover_url = extract_cover_url(item)
        slug = extract_slug_from_url(href)

        next unless title.present? && slug

        chapter_link = item.at_css(".chapter-title a")
        chapter_count = extract_chapter_count(chapter_link&.text)

        ResultTypes::BrowseResult.new(
          id: slug,
          title: title,
          url: normalize_full_url(href),
          cover_url: cover_url,
          language: "en",
          author: nil,
          status: nil,
          last_updated: nil,
          chapter_count: chapter_count,
          description: nil
        )
      end.compact
    end

    # Extract chapter number from URL or title text.
    def extract_chapter_number(href, text)
      match = href&.match(/chapter-(\d+(?:\.\d+)?)/i)
      return match[1] if match

      match = text&.match(/chapter\s*(\d+(?:\.\d+)?)/i)
      return match[1] if match

      nil
    end

    # Extract chapter count from text like "Chapter 20".
    def extract_chapter_count(text)
      return nil if text.blank?
      match = text.match(/chapter\s*(\d+)/i)
      match ? match[1].to_i : nil
    end

    # Parse date from chapter-time text (format: "dd/mm/yyyy" or "views - dd/mm/yyyy").
    def parse_date(text)
      return nil if text.blank?

      # Format: "2177 view - 05/11/2021"
      match = text.match(%r{(\d{2}/\d{2}/\d{4})})
      return Date.strptime(match[1], "%m/%d/%Y") if match

      nil
    rescue Date::Error
      nil
    end

    def looks_like_page_url?(url)
      return false if url.nil? || url.empty?
      return false if url.include?("logo") || url.include?("avatar")
      return false if url.include?("icon") || url.include?("favicon")
      return false if url.include?("loading.svg") || url.include?("x.gif")

      url.match?(/\.(jpg|jpeg|png|webp|gif)/i) || url.include?("cdn")
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

# Register with legacy namespace
module Scrapers
  module Manhwa18
    Adapter = ::Manhwa18::Adapter
  end
end
