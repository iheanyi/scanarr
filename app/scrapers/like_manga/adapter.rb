# frozen_string_literal: true

require "json"
require "nokogiri"
require "base64"

# LikeManga adapter (likemanga.ink, formerly likemanga.io -> mangayy.org)
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/likemanga
#
# LikeManga is a custom manga aggregator (not Madara-based).
# Domain history: likemanga.io -> mangayy.org -> likemanga.ink
#
# Search: GET /?act=searchadvance&f[keyword]={query}&pageNum={page}
# Series: GET /{slug} with selectors #title-detail-manga, .detail-info img
# Chapters: .wp-manga-chapter on series page + AJAX pagination
# Pages: JWT-like token with base64-encoded image array, fallback to img tags
module Scrapers
  module LikeManga
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://likemanga.ink"

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    # Browse latest or popular manga
    # @param sort [String] "latest" or "popular"
    # @param page [Integer] Page number (1-indexed)
    # @param limit [Integer] Ignored
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20)
      sort_value = sort == "popular" ? "top-manga" : "lastest-chap"
      params = {
        "act" => "searchadvance",
        "f[sortby]" => sort_value
      }
      params["pageNum"] = page.to_s if page > 1

      response = http.get(base_url, params: params)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_browse_results(doc)
    rescue StandardError => e
      Rails.logger.error "[LikeManga] Browse error: #{e.message}"
      []
    end

    # Search for manga by title
    # @param query [String] Search term
    # @return [Array<ResultTypes::SearchResult>]
    def search(query)
      params = {
        "act" => "searchadvance",
        "f[keyword]" => query.strip
      }

      response = http.get(base_url, params: params)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_search_results(doc)
    rescue StandardError => e
      Rails.logger.error "[LikeManga] Search error: #{e.message}"
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

      title = doc.at_css("#title-detail-manga")&.text&.strip
      return nil unless title.present?

      ResultTypes::Series.new(
        id: extract_slug(url),
        title: title,
        alt_titles: extract_alt_titles(doc),
        description: doc.at_css("#summary_shortened")&.text&.strip,
        author: extract_author(doc),
        artist: nil,
        status: normalize_status(extract_status(doc)),
        tags: extract_genres(doc),
        series_type: detect_series_type(extract_genres(doc)),
        cover_url: extract_cover(doc),
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[LikeManga] Series error: #{e.message}"
      nil
    end

    # Fetch chapter list for a series
    # @param series_url [String] Series URL or slug
    # @return [Array<ResultTypes::Chapter>]
    def chapters(series_url)
      url = normalize_series_url(series_url)
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      all_chapters = parse_chapters(doc)

      # Check for AJAX pagination
      manga_id = doc.at_css("#title-detail-manga")&.[]("data-manga")&.to_i
      if manga_id && manga_id > 0
        last_page = detect_chapter_last_page(doc)
        if last_page && last_page > 1
          (2..last_page).each do |page|
            ajax_chapters = fetch_ajax_chapters(manga_id, page)
            all_chapters.concat(ajax_chapters)
          end
        end
      end

      all_chapters.uniq { |ch| ch.number }.sort_by { |ch| ch.number.to_f }
    rescue StandardError => e
      Rails.logger.error "[LikeManga] Chapters error: #{e.message}"
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

      # Primary: extract images from JWT-like token
      images = parse_token_images(doc)

      # Fallback: extract from img tags in reading area
      if images.empty?
        images = parse_fallback_images(doc)
      end

      images
    rescue StandardError => e
      Rails.logger.error "[LikeManga] Pages error: #{e.message}"
      []
    end

    # Override to handle LikeManga-specific status values like "Pause" and "In process"
    def normalize_status(status)
      case status&.downcase
      when /in process/ then "ongoing"
      when /pause/ then "hiatus"
      else super
      end
    end

    private

    def base_url
      config["base_url"] || BASE_URL
    end

    # Parse search results from LikeManga search page
    # Selector: div.card-body div.card
    def parse_search_results(doc)
      doc.css("div.card-body div.card").map do |card|
        link = card.at_css("a")
        next unless link

        href = link["href"]
        next unless href.present?

        img = card.at_css("img")
        title = card.at_css(".title-manga")&.text&.strip
        next unless title.present?

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::SearchResult.new(
          id: extract_slug(href),
          title: title,
          url: full_url,
          cover_url: img_attr(img),
          author: nil
        )
      end.compact
    end

    # Parse browse results (same structure as search)
    def parse_browse_results(doc)
      doc.css("div.card-body div.card").map do |card|
        link = card.at_css("a")
        next unless link

        href = link["href"]
        next unless href.present?

        img = card.at_css("img")
        title = card.at_css(".title-manga")&.text&.strip
        next unless title.present?

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::BrowseResult.new(
          id: extract_slug(href),
          title: title,
          url: full_url,
          cover_url: img_attr(img),
          language: "en",
          author: nil,
          status: nil,
          last_updated: nil,
          chapter_count: nil,
          description: nil
        )
      end.compact
    end

    # Extract best image attribute from element
    def img_attr(element)
      return nil unless element

      if element["data-cfsrc"].present?
        element["data-cfsrc"]
      elsif element["data-src"].present?
        element["data-src"]
      elsif element["data-lazy-src"].present?
        element["data-lazy-src"]
      elsif element["srcset"].present?
        element["srcset"].split(" ").first
      else
        element["src"]
      end
    end

    # Extract cover image from series detail page
    def extract_cover(doc)
      img = doc.at_css(".detail-info img")
      img_attr(img)
    end

    # Extract author from series info
    def extract_author(doc)
      author = doc.at_css(".list-info .author p:nth-child(2)")&.text&.strip
      author = nil if author&.downcase == "updating"
      author
    end

    # Extract status from series info
    def extract_status(doc)
      doc.at_css(".list-info .status p:nth-child(2)")&.text&.strip
    end

    # Extract genres from series page
    def extract_genres(doc)
      doc.css('.list-info a[href*="/genres/"]').map { |a| a.text.strip }.reject(&:empty?).uniq
    end

    # Extract alt titles (not directly available in keiyoushi source, but may exist)
    def extract_alt_titles(doc)
      alt_el = doc.at_css(".other-name, .alternative")
      return [] unless alt_el

      alt_el.text.strip.split(/[;,]/).map(&:strip).reject(&:empty?)
    end

    # Parse chapters from HTML
    def parse_chapters(doc)
      doc.css(".wp-manga-chapter").map do |el|
        link = el.at_css("a")
        next unless link

        href = link["href"]
        chapter_text = link.text.strip
        next unless href.present?

        chapter_num = extract_chapter_number(chapter_text)
        date_text = el.at_css(".chapter-release-date")&.text&.strip
        published_at = parse_date(date_text)

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::Chapter.new(
          id: extract_chapter_slug(href),
          title: extract_chapter_title(chapter_text),
          number: chapter_num || "0",
          volume: nil,
          language: "en",
          group: "LikeManga",
          published_at: published_at,
          url: full_url
        )
      end.compact
    end

    # Detect last page number from chapter pagination
    def detect_chapter_last_page(doc)
      doc.css("div.chapters_pagination a:not(.next)").last
        &.[]("onclick")
        &.then { |onclick| onclick.match(/load_list_chapter\((\d+)\)/)&.[](1)&.to_i }
    end

    # Fetch chapters via AJAX endpoint
    def fetch_ajax_chapters(manga_id, page)
      params = {
        "act" => "ajax",
        "code" => "load_list_chapter",
        "manga_id" => manga_id.to_s,
        "page_num" => page.to_s,
        "chap_id" => "0",
        "keyword" => ""
      }

      response = http.get(base_url, params: params)
      return [] unless response.status == 200

      data = JSON.parse(response.body)
      html_string = data["list_chap"]
      return [] unless html_string.present?

      doc = Nokogiri::HTML.fragment(html_string)
      parse_chapters_from_fragment(doc)
    rescue StandardError => e
      Rails.logger.error "[LikeManga] AJAX chapters error: #{e.message}"
      []
    end

    # Parse chapters from an HTML fragment (AJAX response)
    def parse_chapters_from_fragment(doc)
      doc.css(".wp-manga-chapter").map do |el|
        link = el.at_css("a")
        next unless link

        href = link["href"]
        chapter_text = link.text.strip
        next unless href.present?

        chapter_num = extract_chapter_number(chapter_text)
        date_text = el.at_css(".chapter-release-date")&.text&.strip
        published_at = parse_date(date_text)

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::Chapter.new(
          id: extract_chapter_slug(href),
          title: extract_chapter_title(chapter_text),
          number: chapter_num || "0",
          volume: nil,
          language: "en",
          group: "LikeManga",
          published_at: published_at,
          url: full_url
        )
      end.compact
    end

    # Parse images from JWT-like token (primary method)
    # The token is in input#next_img_token, CDN URL in #currentlink
    def parse_token_images(doc)
      token_input = doc.at_css("div.reading input#next_img_token")
      return [] unless token_input

      cdn_url = doc.at_css("div.reading #currentlink")&.[]("value")
      return [] unless cdn_url.present?

      token = token_input["value"]
      return [] unless token.present?

      # Token is JWT-like: header.payload.signature
      parts = token.split(".")
      return [] unless parts.size >= 2

      payload = Base64.decode64(parts[1])
      json_data = JSON.parse(payload)
      encoded_img_array = json_data["data"]
      return [] unless encoded_img_array.present?

      img_array = JSON.parse(Base64.decode64(encoded_img_array))

      img_array.each_with_index.map do |img_path, idx|
        ResultTypes::Page.new(
          index: idx,
          url: "#{cdn_url}/#{img_path}",
          mime_type: guess_mime_type(img_path)
        )
      end
    rescue StandardError => e
      Rails.logger.error "[LikeManga] Token parsing error: #{e.message}"
      []
    end

    # Fallback: parse images from reading area img tags
    def parse_fallback_images(doc)
      images = []

      doc.css("div.reading-detail.box_doc img").each_with_index do |img, idx|
        # Skip images inside noscript tags
        next if img.parent&.name == "noscript"
        src = img_attr(img)
        next unless src.present?
        next unless looks_like_page_url?(src)

        images << ResultTypes::Page.new(
          index: idx,
          url: src.start_with?("http") ? src : "#{base_url}#{src}",
          mime_type: guess_mime_type(src)
        )
      end

      images
    end

    # Extract slug from URL
    def extract_slug(url)
      path = url.to_s.sub(%r{^https?://[^/]+}, "")
      path.split("/").reject(&:empty?).last || url.to_s
    end

    # Extract chapter slug from URL
    def extract_chapter_slug(url)
      url.to_s.split("/").reject(&:empty?).last || url
    end

    # Normalize series URL
    def normalize_series_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.start_with?("/")
        "#{base_url}#{id_or_url}"
      else
        "#{base_url}/#{id_or_url}/"
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

    # Parse date in "MMMM dd, yyyy" format
    def parse_date(text)
      return nil unless text.present?

      Date.strptime(text.strip, "%B %d, %Y").to_time
    rescue Date::Error, ArgumentError
      nil
    end

    def looks_like_page_url?(url)
      return false if url.nil?
      return false if url.include?("logo")
      return false if url.include?("avatar")
      return false if url.include?("icon")
      return false if url.include?("favicon")

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
