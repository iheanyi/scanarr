# frozen_string_literal: true

require "json"
require "nokogiri"

# BatoTo adapter (bato.to / xbato.com / bato.si)
# Reference: https://github.com/keiyoushi/extensions-source (batoto extension)
#
# BatoTo is a popular manga aggregator that supports multiple languages.
# Uses HTML scraping for series/chapters and regex-based image extraction.
# Chapter pages embed image URLs in the page HTML pointing to CDN servers.
#
# Domain history: bato.to -> xbat.tv -> bato.si -> bato.ing (mirrors)
module Batoto
  class Adapter < ::BaseAdapter
    BASE_URL = "https://bato.to"

    # BatoTo supports browse via search with empty query
    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    # Browse latest or popular manga
    # @param sort [String] "latest" or "popular"
    # @param page [Integer] Page number
    # @param limit [Integer] Ignored (uses site default)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20)
      path = case sort.to_s.downcase
             when "popular"
               "/v3x-search?sort=views_a&page=#{page}"
             else
               "/v3x-search?sort=update&page=#{page}"
             end

      response = http.get("#{base_url}#{path}")
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_search_results(doc).map do |result|
        ResultTypes::BrowseResult.new(
          id: result.id,
          title: result.title,
          url: result.url,
          cover_url: result.cover_url,
          language: result.language,
          author: result.author,
          status: nil,
          last_updated: nil,
          chapter_count: nil,
          description: nil
        )
      end
    rescue StandardError => e
      Rails.logger.error "[Batoto] Browse error: #{e.message}"
      []
    end

    # Search for manga by title
    # @param query [String] Search term
    # @return [Array<ResultTypes::SearchResult>]
    def search(query)
      encoded_query = CGI.escape(query)
      response = http.get("#{base_url}/v3x-search?word=#{encoded_query}")
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_search_results(doc)
    rescue StandardError => e
      Rails.logger.error "[Batoto] Search error: #{e.message}"
      []
    end

    # Fetch series details
    # @param id_or_url [String] Series ID, slug, or full URL
    # @return [ResultTypes::Series, nil]
    def series(id_or_url)
      url = normalize_series_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      title = extract_title(doc)
      return nil unless title

      ResultTypes::Series.new(
        id: extract_series_id(url),
        title: title,
        alt_titles: extract_alt_titles(doc),
        description: extract_description(doc),
        author: extract_authors(doc),
        artist: extract_artists(doc),
        status: normalize_status(extract_status(doc)),
        tags: extract_genres(doc),
        series_type: detect_series_type_from_genres(extract_genres(doc)),
        cover_url: extract_cover(doc),
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[Batoto] Series error: #{e.message}"
      nil
    end

    # Fetch chapter list for a series
    # @param series_url [String] Series URL or ID
    # @return [Array<ResultTypes::Chapter>]
    def chapters(series_url)
      url = normalize_series_url(series_url)
      # Append ?start=-1 to get all chapters on one page
      full_url = url.include?("?") ? "#{url}&start=-1" : "#{url}?start=-1"
      response = http.get(full_url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_chapter_list(doc)
    rescue StandardError => e
      Rails.logger.error "[Batoto] Chapters error: #{e.message}"
      []
    end

    # Fetch page image URLs for a chapter
    # @param chapter_url [String] Chapter URL
    # @return [Array<ResultTypes::Page>]
    def pages(chapter_url)
      url = chapter_url.start_with?("http") ? chapter_url : "#{base_url}#{chapter_url}"
      response = http.get(url)
      return [] unless response.status == 200

      extract_page_images(response.body)
    rescue StandardError => e
      Rails.logger.error "[Batoto] Pages error: #{e.message}"
      []
    end

    private

    def base_url
      config["base_url"] || BASE_URL
    end

    # Parse search results from the search page HTML
    # BatoTo search results are in a grid of items with cover images and title links
    def parse_search_results(doc)
      results = []

      # Search results are typically in div elements with series-item structure
      # Each item has an anchor with the series link and an img for the cover
      doc.css("div#series-list div.col, div.grid div.col, div.item-subject").each do |card|
        link = card.css("a[href*='/title/']").first ||
               card.css("a[href*='/series/']").first
        next unless link

        href = link["href"]
        title = link.text.strip
        title = card.css("a.item-title").first&.text&.strip || title if title.empty?

        # Try multiple selectors for the cover image
        img = card.css("img").first
        cover_url = img&.[]("src") || img&.[]("data-src")

        next if title.empty? || href.nil?

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        results << ResultTypes::SearchResult.new(
          id: extract_series_id(href),
          title: title,
          url: full_url,
          cover_url: normalize_cover_url(cover_url),
          author: nil
        )
      end

      # Fallback: try a broader selector if no results found
      if results.empty?
        doc.css("a[href*='/title/']").each do |link|
          href = link["href"]
          next if href.nil?
          next unless href.match?(%r{/title/\d+})

          # Skip navigation/header links
          title = link.text.strip
          next if title.empty? || title.length < 2

          img = link.css("img").first || link.parent&.css("img")&.first
          cover_url = img&.[]("src") || img&.[]("data-src")

          full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

          results << ResultTypes::SearchResult.new(
            id: extract_series_id(href),
            title: title,
            url: full_url,
            cover_url: normalize_cover_url(cover_url),
            author: nil
          )
        end

        # Deduplicate by ID
        results.uniq! { |r| r.id }
      end

      results
    end

    # Extract the series title from the page
    def extract_title(doc)
      # Try h3 > a pattern first (common BatoTo layout)
      title_el = doc.at_css("h3 a")
      return title_el.text.strip if title_el && title_el.text.strip.present?

      # Fallback to h1
      title_el = doc.at_css("h1")
      return title_el.text.strip if title_el && title_el.text.strip.present?

      # Fallback to page title
      title_text = doc.at_css("title")&.text&.strip
      return nil unless title_text

      # Clean up title - remove site name suffix
      title_text
        .gsub(/ [-–|] Bato\.To.*$/i, "")
        .gsub(/ [-–|] Read Free.*$/i, "")
        .gsub(/ Manga$/i, "")
        .strip
        .presence
    end

    # Extract alternative titles
    def extract_alt_titles(doc)
      alt_titles = []

      # Look for alternative names section
      doc.css("span.text-muted, div.alias-set, div.text-muted").each do |el|
        text = el.text.strip
        next if text.empty? || text.length > 500

        # Check if this looks like alt titles (contains separator)
        if text.include?("/") || text.include?(";")
          alt_titles.concat(text.split(%r{[/;]}).map(&:strip).reject(&:empty?))
        end
      end

      alt_titles.uniq
    end

    # Extract description
    def extract_description(doc)
      # Look for description/synopsis section
      desc_el = doc.at_css("div.limit-html, div.prose, div.summary, div[class*='description']")
      return nil unless desc_el

      # Strip HTML tags and clean up
      text = desc_el.text.strip
      text.gsub(/\s+/, " ").strip.presence
    end

    # Extract authors from author links
    def extract_authors(doc)
      authors = doc.css("a[href*='/author']").map { |a| a.text.strip }.reject(&:empty?)
      authors.first
    end

    # Extract artists (often same as authors on BatoTo)
    def extract_artists(doc)
      # BatoTo doesn't always distinguish authors from artists
      # Try to find artist-specific links
      doc.css("a[href*='/artist']").map { |a| a.text.strip }.reject(&:empty?).first
    end

    # Extract publication status
    def extract_status(doc)
      # Look for status indicator
      doc.css("span.text-success, span.text-warning, span.text-danger, div.attr-item").each do |el|
        text = el.text.strip.downcase
        return text if text.match?(/ongoing|completed|hiatus|cancelled|dropped|discontinued/)
      end

      # Try broader text search
      doc.text.scan(/(?:status|upload status)[:\s]+(\w+)/i).flatten.first
    end

    # Extract genres/tags
    def extract_genres(doc)
      genres = []

      # Look for genre links
      doc.css("a[href*='/genre/'], a[href*='/tag/'], span.badge").each do |el|
        text = el.text.strip
        genres << text unless text.empty? || text.length > 50
      end

      # Fallback: look for genre container with whitespace-nowrap spans
      if genres.empty?
        doc.css("div.flex-wrap span.whitespace-nowrap, div.attr-item span").each do |span|
          text = span.text.strip
          genres << text unless text.empty? || text.length > 50
        end
      end

      genres.uniq
    end

    # Extract cover image URL
    def extract_cover(doc)
      # Try multiple selectors for cover image
      selectors = [
        "img[src*='/attachs/']",
        "img[src*='/media/']",
        "div.cover img",
        "div.thumb img",
        "img.shadow"
      ]

      selectors.each do |selector|
        img = doc.at_css(selector)
        if img
          src = img["src"] || img["data-src"]
          return normalize_cover_url(src) if src
        end
      end

      # Broader fallback
      doc.css("img").each do |img|
        src = img["src"] || img["data-src"]
        next unless src
        next if src.include?("avatar") || src.include?("icon") || src.include?("logo")
        return normalize_cover_url(src) if src.match?(/\.(jpg|jpeg|png|webp)/i)
      end

      nil
    end

    # Parse chapter list from the series page
    def parse_chapter_list(doc)
      chapters = []

      # BatoTo chapter links are in div.space-x-1 containers
      # Pattern: <div class="space-x-1"><a href="/chapter/123">Ch.45</a><span>: Title</span></div>
      doc.css("div.space-x-1").each do |container|
        link = container.at_css("a[href*='/chapter/']")
        next unless link

        href = link["href"]
        chapter_text = link.text.strip

        # Skip version indicators (e.g., "v20251008")
        next if chapter_text.match?(/^v\d+$/)

        # Extract optional title from span
        title_span = container.at_css("span")
        chapter_title = title_span&.text&.strip&.sub(/^:\s*/, "")

        # Extract chapter number
        chapter_num = extract_chapter_number(chapter_text)

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        chapters << ResultTypes::Chapter.new(
          id: href.split("/").last,
          title: chapter_title.presence,
          number: chapter_num || chapter_text,
          volume: extract_volume_number(chapter_text),
          language: "en",
          group: nil,
          published_at: nil,
          url: full_url
        )
      end

      # Fallback: try anchor tags with chapter links directly
      if chapters.empty?
        doc.css("a[href*='/chapter/']").each do |link|
          href = link["href"]
          chapter_text = link.text.strip

          next if chapter_text.empty?
          next if chapter_text.match?(/^v\d+$/)

          chapter_num = extract_chapter_number(chapter_text)
          full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

          chapters << ResultTypes::Chapter.new(
            id: href.split("/").last,
            title: nil,
            number: chapter_num || chapter_text,
            volume: nil,
            language: "en",
            group: nil,
            published_at: nil,
            url: full_url
          )
        end
      end

      chapters.uniq { |ch| ch.id }.sort_by { |ch| ch.number.to_f }
    end

    # Extract page images from chapter HTML
    # BatoTo embeds image URLs directly in the page HTML or in JS variables
    def extract_page_images(body)
      images = []

      # Method 1: Extract from JavaScript variable "const imgHttps" or "var images"
      js_images = extract_js_images(body)
      unless js_images.empty?
        js_images.each_with_index do |url, idx|
          images << ResultTypes::Page.new(
            index: idx + 1,
            url: url,
            mime_type: guess_mime_type(url)
          )
        end
        return images
      end

      # Method 2: Find CDN image URLs via regex
      # BatoTo uses CDN servers like i{N}.{domain}.com/media/...
      cdn_pattern = %r{https?://[a-zA-Z]\d{1,2}\.[a-zA-Z0-9.-]+\.com/media/[^\s"'<>]+\.(?:webp|jpg|jpeg|png)}i
      cdn_urls = body.scan(cdn_pattern).uniq

      unless cdn_urls.empty?
        cdn_urls.each_with_index do |url, idx|
          images << ResultTypes::Page.new(
            index: idx + 1,
            url: url,
            mime_type: guess_mime_type(url)
          )
        end
        return images
      end

      # Method 3: Parse HTML img tags as fallback
      doc = Nokogiri::HTML(body)
      doc.css("div.viewer-cnt img, div.page-img img, img[data-page]").each_with_index do |img, idx|
        src = img["src"] || img["data-src"]
        next unless src && looks_like_page_url?(src)

        images << ResultTypes::Page.new(
          index: idx + 1,
          url: src.start_with?("http") ? src : "#{base_url}#{src}",
          mime_type: guess_mime_type(src)
        )
      end

      images
    end

    # Extract images from JavaScript variables in the page
    def extract_js_images(body)
      # Try "const imgHttps = [...];"
      match = body.match(/const\s+imgHttps\s*=\s*(\[.*?\]);/m)
      if match
        return parse_js_array(match[1])
      end

      # Try "var images = {...};"
      match = body.match(/var\s+images\s*=\s*(\{.*?\});/m)
      if match
        begin
          data = JSON.parse(match[1])
          # Images are a hash of page_num => url
          return data.sort_by { |k, _| k.to_i }.map { |_, v| v }
        rescue JSON::ParserError
          # Fall through to next method
        end
      end

      # Try "var images = [...];"
      match = body.match(/var\s+images\s*=\s*(\[.*?\]);/m)
      if match
        return parse_js_array(match[1])
      end

      # Try encoded format: [[0,"url"]] pattern
      encoded_urls = body.scan(/\[\[0,\\?"([^"]+\.(?:webp|jpg|jpeg|png))[^"]*\\?"\]\]/)
      unless encoded_urls.empty?
        return encoded_urls.flatten.map { |url| url.gsub(/\\&quot;/, "") }
      end

      []
    end

    # Parse a JavaScript array string into Ruby array
    def parse_js_array(js_str)
      # Clean up JS syntax to valid JSON
      cleaned = js_str.gsub("'", '"')
      JSON.parse(cleaned)
    rescue JSON::ParserError
      # Try regex extraction as fallback
      js_str.scan(/"(https?:\/\/[^"]+)"/).flatten
    end

    # Normalize a series URL from various input formats
    def normalize_series_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.match?(%r{^/})
        "#{base_url}#{id_or_url}"
      elsif id_or_url.match?(/^\d+/)
        "#{base_url}/title/#{id_or_url}"
      else
        "#{base_url}/title/#{id_or_url}"
      end
    end

    # Extract the series ID from a URL or path
    # Prefers full slug (e.g., "81514-one-piece") over bare numeric ID
    def extract_series_id(url_or_path)
      # Extract ID with slug: /title/12345-series-name
      match = url_or_path.match(%r{/title/(\d+-[^/?]+)})
      return match[1] if match

      # Bare numeric ID
      match = url_or_path.match(%r{/title/(\d+)})
      return match[1] if match

      url_or_path.split("/").last
    end

    # Extract chapter number from text like "Ch.45", "Chapter 45.5", "#45"
    def extract_chapter_number(text)
      return nil unless text

      # Match "Ch.45", "Ch 45.5", "Chapter 45"
      match = text.match(/ch(?:apter)?[.\s#]*(\d+(?:\.\d+)?)/i)
      return match[1] if match

      # Match standalone number
      match = text.match(/^(\d+(?:\.\d+)?)$/)
      return match[1] if match

      # Match "#45" pattern
      match = text.match(/#(\d+(?:\.\d+)?)/)
      return match[1] if match

      nil
    end

    # Extract volume number from text
    def extract_volume_number(text)
      return nil unless text

      match = text.match(/vol(?:ume)?[.\s]*(\d+)/i)
      match&.[](1)
    end

    # Normalize cover URL to absolute
    def normalize_cover_url(url)
      return nil unless url
      return url if url.start_with?("http")
      "#{base_url}#{url}"
    end

    # Detect series type from genre tags
    def detect_series_type_from_genres(genres)
      genres_lower = (genres || []).map(&:downcase)
      return "manhwa" if genres_lower.any? { |t| t.include?("manhwa") || t.include?("korean") }
      return "manhua" if genres_lower.any? { |t| t.include?("manhua") || t.include?("chinese") }
      "manga"
    end

    def looks_like_page_url?(url)
      return false if url.nil?
      return false if url.include?("logo")
      return false if url.include?("avatar")
      return false if url.include?("icon")
      return false if url.include?("favicon")

      url.match?(/\.(jpg|jpeg|png|webp|gif)/i) || url.include?("media")
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
  module Batoto
    Adapter = ::Batoto::Adapter
  end
end
