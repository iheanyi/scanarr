# frozen_string_literal: true

require "nokogiri"

# DrakeScans adapter (drakecomic.org)
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/drakescans
#
# DrakeScans is a WordPress/MangaThemesia-based manga site focused on manhua translations.
# Domain history: drakescans.com -> igniscomic.com -> drakecomic.org
# Uses MangaThemesia theme selectors (NOT Madara).
#
# Search: GET /manga/?title={query}&page={page}
# Series: GET /manga/{slug}/
# Chapters: Listed on series page in #chapterlist li
# Pages: GET /{chapter-url}/ with images in div#readerarea img or JS "images" array
#
# Special: Strips Jetpack CDN prefix (https://i[0-9].wp.com/) from image URLs
module Scrapers
  module DrakeScans
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://drakecomic.org"

    JETPACK_CDN_REGEX = /\Ahttps:\/\/i\d\.wp\.com\//

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    # Browse manga via MangaThemesia search with order parameter
    # @param sort [String] "latest" or "popular"
    # @param page [Integer] Page number (1-indexed)
    # @param limit [Integer] Ignored (uses site default)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = filters
      order = sort == "popular" ? "popular" : "update"
      response = http.get("#{base_url}/manga/", params: { "order" => order, "page" => page.to_s })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_browse_results(doc)
    rescue StandardError => e
      Rails.logger.error "[DrakeScans] Browse error: #{e.message}"
      []
    end

    # Search for manga by title
    # @param query [String] Search term
    # @return [Array<ResultTypes::SearchResult>]
    def search(query, filters: {})
      _ = filters
      response = http.get("#{base_url}/manga/", params: { "title" => query, "page" => "1" })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_search_results(doc)
    rescue StandardError => e
      Rails.logger.error "[DrakeScans] Search error: #{e.message}"
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
      parse_series(doc, url)
    rescue StandardError => e
      Rails.logger.error "[DrakeScans] Series error: #{e.message}"
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
      parse_chapters(doc)
    rescue StandardError => e
      Rails.logger.error "[DrakeScans] Chapters error: #{e.message}"
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
      parse_pages(doc, response.body)
    rescue StandardError => e
      Rails.logger.error "[DrakeScans] Pages error: #{e.message}"
      []
    end

    private

    # Parse search results using MangaThemesia selectors
    def parse_search_results(doc)
      doc.css(".utao .uta .imgu, .listupd .bs .bsx").map do |element|
        link = element.at_css("a")
        next unless link

        href = link["href"]
        title = link["title"]&.strip
        next unless title.present? && href.present?

        img = element.at_css("img")
        cover_url = img_attr(img)

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

    # Parse browse results (same selectors as search for MangaThemesia)
    def parse_browse_results(doc)
      doc.css(".utao .uta .imgu, .listupd .bs .bsx").map do |element|
        link = element.at_css("a")
        next unless link

        href = link["href"]
        title = link["title"]&.strip
        next unless title.present? && href.present?

        img = element.at_css("img")
        cover_url = img_attr(img)

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

    # Parse series details from MangaThemesia series page
    def parse_series(doc, url)
      details = doc.at_css("div.bigcontent, div.animefull, div.main-info, div.postbody")
      return nil unless details

      title = details.at_css("h1.entry-title, .ts-breadcrumb li:last-child span")&.text&.strip
      return nil unless title.present?

      author = extract_themesia_meta(details, %w[Author])
      artist = extract_themesia_meta(details, %w[Artist])
      status_text = extract_themesia_meta(details, %w[Status])
      series_type_text = extract_themesia_meta(details, %w[Type])

      description = details.css(".desc, .entry-content[itemprop=description]")
                          .map { |el| el.text.strip }.join("\n").strip.presence

      alt_name = details.at_css(".alternative, .wd-full:contains('alt') span, .alter, .seriestualt")&.text&.strip

      genres = details.css("div.gnr a, .mgen a, .seriestugenre a").map { |a| a.text.strip }.reject(&:empty?).uniq

      # Add type to genres if present (MangaThemesia convention)
      if series_type_text.present? && genres.none? { |g| g.downcase == series_type_text.downcase }
        genres << series_type_text.capitalize
      end

      cover = details.css(".infomanga > div[itemprop=image] img, .thumb img").map { |img| img_attr(img) }.first

      ResultTypes::Series.new(
        id: extract_slug(url),
        title: title,
        alt_titles: alt_name.present? ? alt_name.split(/[;,]/).map(&:strip).reject(&:empty?) : [],
        description: description,
        author: clean_placeholder(author),
        artist: clean_placeholder(artist),
        status: normalize_status(status_text),
        tags: genres,
        series_type: detect_series_type(genres, series_type_text),
        cover_url: cover,
        url: url
      )
    end

    # Parse chapters from MangaThemesia chapter list
    def parse_chapters(doc)
      doc.css("div.bxcl li, div.cl li, #chapterlist li, ul li:has(div.chbox):has(div.eph-num)").map do |li|
        link = li.at_css("a")
        next unless link

        href = link["href"]
        next unless href.present?

        chapter_text = li.at_css(".lch a, .chapternum")&.text&.strip
        chapter_text ||= link.text.strip

        chapter_num = extract_chapter_number(chapter_text)

        date_text = li.at_css(".chapterdate")&.text&.strip
        published_at = parse_themesia_date(date_text)

        full_url = ensure_full_url(href)

        ResultTypes::Chapter.new(
          id: extract_chapter_slug(href),
          title: extract_chapter_title(chapter_text),
          number: chapter_num || "0",
          volume: nil,
          language: "en",
          group: "Drake Scans",
          published_at: published_at,
          url: full_url
        )
      end.compact.uniq { |ch| ch.number }.sort_by { |ch| ch.number.to_f }
    end

    # Parse page images from MangaThemesia reader
    # First tries HTML img tags, then falls back to JS "images" JSON array
    def parse_pages(doc, body)
      images = []

      # Primary: div#readerarea img
      doc.css("div#readerarea img").each_with_index do |img, idx|
        src = img_attr(img)
        next unless src.present?
        next unless looks_like_page_url?(src)

        # Strip Jetpack CDN prefix
        src = strip_jetpack_cdn(src)

        images << ResultTypes::Page.new(
          index: idx,
          url: src,
          mime_type: guess_mime_type(src)
        )
      end

      # Fallback: extract from JS "images" JSON array
      if images.empty?
        js_images = extract_js_image_list(body)
        js_images.each_with_index do |src, idx|
          src = strip_jetpack_cdn(src)

          images << ResultTypes::Page.new(
            index: idx,
            url: src,
            mime_type: guess_mime_type(src)
          )
        end
      end

      images
    end

    # Extract image URLs from JavaScript "images" JSON array in page source
    def extract_js_image_list(body)
      match = body.match(/"images"\s*:\s*(\[.*?\])/m)
      return [] unless match

      JSON.parse(match[1])
    rescue JSON::ParserError
      []
    end

    # Strip Jetpack CDN prefix from image URLs
    # e.g., https://i0.wp.com/drakecomic.org/... -> https://drakecomic.org/...
    def strip_jetpack_cdn(url)
      url.sub(JETPACK_CDN_REGEX, "https://")
    end

    # Extract metadata value from MangaThemesia info tables/spans
    def extract_themesia_meta(doc, labels)
      labels.each do |label|
        # Try .infotable format
        el = doc.at_css(".infotable tr:contains('#{label}') td:last-child")
        return el.text.strip if el&.text&.strip.present?

        # Try .tsinfo format
        el = doc.at_css(".tsinfo .imptdt:contains('#{label}') i")
        return el.text.strip if el&.text&.strip.present?

        # Try .fmed format
        el = doc.at_css(".fmed b:contains('#{label}')")
        return el.next_element&.text&.strip if el&.next_element
      end
      nil
    end

    # Get best image URL from an img element (data-lazy-src > data-src > data-cfsrc > src)
    def img_attr(img)
      return nil unless img
      if img["data-lazy-src"].present?
        img["data-lazy-src"]
      elsif img["data-src"].present?
        img["data-src"]
      elsif img["data-cfsrc"].present?
        img["data-cfsrc"]
      else
        img["src"]
      end
    end

    # Clean placeholder values like "-" or "N/A"
    def clean_placeholder(value)
      return nil if value.nil? || value.blank? || value == "-" || value.downcase == "n/a"
      value
    end

    # Extract slug from manga URL (e.g., /manga/some-series/ -> "some-series")
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

    def ensure_full_url(href)
      href.start_with?("http") ? href : "#{base_url}#{href}"
    end

    # Extract chapter number from text like "Chapter 45", "Chapter 45.5"
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

    # Parse MangaThemesia date format (e.g., "January 15, 2024")
    def parse_themesia_date(text)
      return nil unless text.present?

      Date.strptime(text, "%B %d, %Y").to_time
    rescue Date::Error, ArgumentError
      begin
        Time.parse(text)
      rescue ArgumentError
        nil
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

    # Detect series type from genre tags and type metadata
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
