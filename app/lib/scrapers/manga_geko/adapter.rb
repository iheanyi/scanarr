# frozen_string_literal: true

require "nokogiri"
require "json"

# MangaGeko adapter (mgeko.cc / mangamob.com)
#
# MangaGeko is a manga aggregator with a custom frontend.
# Domain history: mangageko.com -> mgeko.cc (primary), mangamob.com (mirror)
#
# Search: GET /ajax/manga/search/suggest?keyword={query} -> JSON with HTML
# Browse: GET /browse-comics/?filter={Updated|Views}&results={page}
# Series: GET /manga/item/{slug}/ -> HTML
# Chapters: GET /get/chapters/?manga_id={id} -> JSON
# Pages: GET /chapter/en/{slug}/ -> HTML with img.lazy[data-src]
module Scrapers
  module MangaGeko
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://www.mgeko.cc"

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    # Browse manga catalog
    # @param sort [String] "latest" (by update) or "popular" (by views)
    # @param page [Integer] Page number (1-indexed)
    # @param limit [Integer] Ignored (uses site default)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = filters
      filter = sort == "popular" ? "Views" : "Updated"
      response = http.get("#{base_url}/browse-comics/", params: { "filter" => filter, "results" => page.to_s })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_browse_results(doc)
    rescue StandardError => e
      Rails.logger.error "[MangaGeko] Browse error: #{e.message}"
      []
    end

    # Search for manga by keyword
    # @param query [String] Search term
    # @return [Array<ResultTypes::SearchResult>]
    def search(query, filters: {})
      _ = filters
      response = http.get("#{base_url}/ajax/manga/search/suggest", params: { "keyword" => query })
      return [] unless response.status == 200

      data = JSON.parse(response.body)
      return [] unless data["status"]

      parse_search_results(data["html"])
    rescue StandardError => e
      Rails.logger.error "[MangaGeko] Search error: #{e.message}"
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
      parse_series(doc, url, response.body)
    rescue StandardError => e
      Rails.logger.error "[MangaGeko] Series error: #{e.message}"
      nil
    end

    # Fetch chapter list for a series
    # Requires the manga_id which is extracted from the series page
    # @param series_url [String] Series URL or slug
    # @return [Array<ResultTypes::Chapter>]
    def chapters(series_url)
      url = normalize_series_url(series_url)
      response = http.get(url)
      return [] unless response.status == 200

      manga_id = extract_manga_id(response.body)
      return [] unless manga_id

      series_slug = extract_slug(url)

      chapters_response = http.get("#{base_url}/get/chapters/", params: { "manga_id" => manga_id.to_s })
      return [] unless chapters_response.status == 200

      data = JSON.parse(chapters_response.body)
      parse_chapters(data["chapters"] || [], series_slug)
    rescue StandardError => e
      Rails.logger.error "[MangaGeko] Chapters error: #{e.message}"
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
      Rails.logger.error "[MangaGeko] Pages error: #{e.message}"
      []
    end

    private

    # Parse search results from the AJAX HTML response
    def parse_search_results(html)
      doc = Nokogiri::HTML.fragment(html)

      doc.css("a.nav-item:not(.nav-bottom)").map do |link|
        href = link["href"]
        next unless href.present?

        title = link.at_css("h3.manga-name")&.text&.strip
        next unless title.present?

        img = link.at_css("img.manga-poster-img")
        cover_url = img&.[]("src")

        full_url = ensure_full_url(href)

        ResultTypes::SearchResult.new(
          id: extract_slug(href),
          title: title,
          url: full_url,
          cover_url: cover_url,
          author: nil
        )
      end.compact
    end

    # Parse browse results from the browse page HTML
    def parse_browse_results(doc)
      doc.css(".manga-card, .film_list-wrap .flw-item, .browse-item").map do |card|
        link = card.at_css("a[href*='/manga/item/']")
        next unless link

        href = link["href"]
        title_el = card.at_css("h3 a, h3.manga-name a, .manga-name")
        title = title_el&.text&.strip || link["title"]&.strip
        next unless title.present?

        img = card.at_css("img")
        cover_url = img&.[]("src") || img&.[]("data-src")

        full_url = ensure_full_url(href)

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

    # Parse series details from the manga item page
    def parse_series(doc, url, body)
      title = doc.at_css("h2.manga-name, h1.manga-name")&.text&.strip
      return nil unless title.present?

      alt_title = doc.at_css(".manga-name-or")&.text&.strip
      alt_titles = if alt_title.present? && alt_title != "updating"
        alt_title.split(/[;,]/).map(&:strip).reject(&:empty?)
      else
        []
      end

      cover_img = doc.at_css(".manga-poster-img")
      cover_url = cover_img&.[]("src") || cover_img&.[]("data-src")

      description = doc.at_css(".description-modal")&.text&.strip
      description ||= doc.at_css(".description")&.text&.strip

      type_text = extract_anisc_info(doc, "Type")
      status_text = extract_anisc_info(doc, "Status")
      author = extract_author(doc)

      genres = doc.css(".anisc-detail .genres a").map { |a| a.text.strip }.reject(&:empty?).uniq

      ResultTypes::Series.new(
        id: extract_slug(url),
        title: title,
        alt_titles: alt_titles,
        description: description,
        author: author,
        artist: nil,
        status: normalize_status(status_text),
        tags: genres,
        series_type: detect_series_type(genres, type_text),
        cover_url: cover_url,
        url: url
      )
    end

    # Parse chapters from the JSON API response
    def parse_chapters(chapters_data, series_slug)
      chapters_data.map do |ch|
        chapter_number_raw = ch["chapter_number"].to_s
        chapter_slug = ch["chapter_slug"].to_s

        # chapter_number format: "96-eng-li" -> extract "96"
        match = chapter_number_raw.match(/\A(\d+(?:\.\d+)?)/)
        chapter_num = match ? match[1] : nil
        next unless chapter_num

        chapter_url = "#{base_url}/chapter/en/#{chapter_slug}/"

        ResultTypes::Chapter.new(
          id: chapter_slug,
          title: nil,
          number: chapter_num,
          volume: nil,
          language: "en",
          group: "MangaGeko",
          published_at: nil,
          url: chapter_url
        )
      end.compact.sort_by { |ch| ch.number.to_f }
    end

    # Parse page images from the chapter reader page
    def parse_pages(doc)
      images = []

      # Primary: img.lazy[data-src] inside #chapter-images or reading area
      doc.css("#chapter-images img.lazy, .container-reader-chapter img.lazy, img.lazy[data-src]").each_with_index do |img, idx|
        src = img["data-src"]
        next unless src.present?
        next unless looks_like_page_url?(src)

        images << ResultTypes::Page.new(
          index: idx,
          url: src,
          mime_type: guess_mime_type(src)
        )
      end

      # Fallback: any img with data-src in reading containers
      if images.empty?
        doc.css("img[data-src]").each_with_index do |img, idx|
          src = img["data-src"]
          next unless src.present?
          next unless looks_like_page_url?(src)

          images << ResultTypes::Page.new(
            index: idx,
            url: src,
            mime_type: guess_mime_type(src)
          )
        end
      end

      images
    end

    # Extract manga_id from the series page body (used for chapter API)
    def extract_manga_id(body)
      match = body.match(/manga_id[:\s]*(\d+)/)
      match&.[](1)
    end

    # Extract info values from .anisc-info section
    def extract_anisc_info(doc, label)
      doc.css(".anisc-info .item").each do |item|
        head = item.at_css(".item-head")&.text&.strip
        if head&.downcase&.include?(label.downcase)
          value = item.at_css(".name, a.name")&.text&.strip
          return value if value.present?
        end
      end
      nil
    end

    # Extract author from the series page
    def extract_author(doc)
      author_link = doc.at_css("a[href*='/author/']")
      author_text = author_link&.text&.strip
      return nil if author_text.blank? || author_text.downcase == "updating"
      author_text
    end

    def normalize_series_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.start_with?("/")
        "#{base_url}#{id_or_url}"
      else
        "#{base_url}/manga/item/#{id_or_url}/"
      end
    end

    def ensure_full_url(href)
      href.start_with?("http") ? href : "#{base_url}#{href}"
    end

    # Extract slug from manga URL (e.g., /manga/item/some-series/ -> "some-series")
    def extract_slug(url)
      match = url.to_s.match(%r{/manga/item/([^/?]+)})
      match ? match[1].chomp("/") : url.to_s.split("/").reject(&:empty?).last
    end

    def looks_like_page_url?(url)
      return false if url.nil?
      return false if url.include?("logo")
      return false if url.include?("avatar")
      return false if url.include?("icon")
      return false if url.include?("favicon")

      url.match?(/\.(jpg|jpeg|png|webp|gif)/i) || url.include?("cdn") || url.include?("imgsrv")
    end

    def guess_mime_type(url)
      case url.downcase
      when /\.png/ then "image/png"
      when /\.gif/ then "image/gif"
      when /\.webp/ then "image/webp"
      else "image/jpeg"
      end
    end

    def detect_series_type(tags, type_text = nil)
      if type_text.present?
        case type_text.downcase
        when /manhwa/, /korean/ then return "manhwa"
        when /manhua/, /chinese/ then return "manhua"
        when /manga/ then return "manga"
        end
      end

      tags_lower = (tags || []).map(&:downcase)
      return "manhwa" if tags_lower.any? { |t| t.include?("manhwa") || t.include?("korean") }
      return "manhua" if tags_lower.any? { |t| t.include?("manhua") || t.include?("chinese") }
      "manga"
    end
  end
  end
end
