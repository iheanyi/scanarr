# frozen_string_literal: true

# AsuraScans adapter
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/asurascans
# Note: AsuraScans uses a Next.js frontend, NOT WordPress/Madara
module AsuraScans
  class Adapter < ::BaseAdapter
    BASE_URL = "https://asuracomic.net"

    def search(query)
      # AsuraScans search via query param
      response = http.get("#{BASE_URL}/series", params: { name: query })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      doc.css(".grid > a").map do |link|
        title = link.css("span.block").first&.text&.strip
        href = link["href"]
        img = link.css("img").first

        next unless title && href

        # Ensure proper URL construction
        full_url = if href.start_with?("http")
                     href
                   elsif href.start_with?("/")
                     "#{BASE_URL}#{href}"
                   else
                     "#{BASE_URL}/#{href}"
                   end

        ResultTypes::SearchResult.new(
          id: href.split("/").last,
          title: title,
          url: full_url,
          cover_url: img&.[]("src"),
          author: nil
        )
      end.compact
    rescue StandardError => e
      Rails.logger.error "[AsuraScans] Search error: #{e.message}"
      []
    end

    def series(id_or_url)
      url = normalize_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      # Title - look for the series title specifically
      title = doc.at_css("span.text-xl")&.text&.strip
      title ||= doc.css("h1, h2").first&.text&.strip
      cover = doc.css("img[alt*='poster'], img[alt*='cover']").first&.[]("src")
      description = doc.css("[class*='description'], [class*='summary']").first&.text&.strip

      # Extract metadata
      info_section = doc.css("[class*='info'], [class*='detail']").first
      author = extract_text_after(info_section, "Author")
      artist = extract_text_after(info_section, "Artist")
      status = extract_text_after(info_section, "Status")

      # Extract tags from buttons (genre buttons are after certain common ones)
      tags = extract_tags(doc)

      ResultTypes::Series.new(
        id: url.split("/").last,
        title: title,
        alt_titles: [],
        description: description,
        author: author,
        artist: artist,
        status: normalize_status(status),
        tags: tags,
        series_type: detect_series_type(tags),
        cover_url: cover,
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[AsuraScans] Series error: #{e.message}"
      nil
    end

    def chapters(series_url)
      url = normalize_url(series_url)
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      # Chapters are in links with chapter in href (using /chapter/ not /chapter-)
      chapter_links = doc.css("a[href*='/chapter/']")

      chapter_links.map do |link|
        href = link["href"]
        # Ensure proper URL - add leading slash if needed
        href = "/#{href}" unless href.start_with?("/") || href.start_with?("http")
        full_url = href.start_with?("http") ? href : "#{BASE_URL}#{href}"

        # Extract chapter number from URL (format: .../chapter/123 or .../chapter/123.5)
        chapter_num = href[/\/chapter\/(\d+(?:\.\d+)?)/, 1] || extract_chapter_number(link.text)
        full_text = link.text.strip

        # Extract title (before the date) and published_at (the date part)
        title_text, published_at = extract_chapter_title_and_date(full_text)

        # Check for premium/locked chapters
        is_locked = link.css("[class*='lock']").any? || full_text.include?("🔒")

        ResultTypes::Chapter.new(
          id: href.split("/").last,
          title: is_locked ? "🔒 #{title_text}" : title_text,
          number: chapter_num || "0",
          volume: nil,
          language: "en",
          group: "Asura Scans",
          published_at: published_at,
          url: full_url
        )
      end.uniq { |ch| ch.number }.sort_by { |ch| ch.number.to_f }
    rescue StandardError => e
      Rails.logger.error "[AsuraScans] Chapters error: #{e.message}"
      []
    end

    def pages(chapter_url)
      response = http.get(chapter_url)
      return [] unless response.status == 200

      # AsuraScans uses Next.js with images in script data
      # Look for self.__next_f.push patterns
      images = []

      # Try to extract from Next.js data
      response.body.scan(/self\.__next_f\.push\(\[.*?"pages":\s*(\[.*?\]).*?\]\)/) do |match|
        begin
          # Unescape the JSON
          json_str = match[0].gsub('\\"', '"').gsub('\\\\', '\\')
          pages_data = JSON.parse(json_str)
          pages_data.each_with_index do |page, idx|
            url = page["url"] || page["src"] || page
            next unless url.is_a?(String)
            images << ResultTypes::Page.new(index: idx, url: url, mime_type: "image/webp")
          end
        rescue JSON::ParserError
          # Continue trying other patterns
        end
      end

      # Fallback: look for image tags directly
      if images.empty?
        doc = Nokogiri::HTML(response.body)
        doc.css("[class*='reader'] img, [class*='chapter'] img").each_with_index do |img, idx|
          src = img["src"] || img["data-src"]
          next unless src && !src.include?("logo") && !src.include?("avatar")
          images << ResultTypes::Page.new(index: idx, url: src, mime_type: "image/webp")
        end
      end

      images
    rescue StandardError => e
      Rails.logger.error "[AsuraScans] Pages error: #{e.message}"
      []
    end

    private

    def normalize_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.include?("/")
        "#{BASE_URL}/#{id_or_url}"
      else
        "#{BASE_URL}/series/#{id_or_url}"
      end
    end

    def extract_text_after(node, label)
      return nil unless node
      text = node.text
      match = text.match(/#{label}[:\s]*([^\n]+)/i)
      match[1]&.strip if match
    end

    def extract_chapter_number(text)
      return nil unless text
      match = text.match(/chapter[- ]?(\d+(?:\.\d+)?)/i)
      match[1] if match
    end

    def normalize_status(status)
      case status&.downcase
      when /ongoing/, /releasing/ then "ongoing"
      when /complete/, /finished/ then "completed"
      when /hiatus/ then "hiatus"
      when /cancel/, /dropped/ then "cancelled"
      else "ongoing"
      end
    end

    def extract_tags(doc)
      # Genre buttons are in a flex container with gap-3 class
      genre_container = doc.at_css(".flex.flex-row.flex-wrap.gap-3")
      return [] unless genre_container

      genre_container.css("button").map { |btn| btn.text.strip }
                     .reject { |text| text.empty? || text.length > 30 }
                     .uniq
    end

    def extract_chapter_title_and_date(text)
      # Text format: "Chapter 200Side Story 21 { THE END }July 13th 2024"
      # or "Chapter 199Side Story 20May 24th 2023"
      # Extract date pattern at the end
      date_pattern = /([A-Z][a-z]+\s+\d{1,2}(?:st|nd|rd|th)?\s+\d{4})\s*$/
      if match = text.match(date_pattern)
        date_str = match[1]
        title = text.sub(date_pattern, "").strip
        published_at = parse_date(date_str)
        [title, published_at]
      else
        [text, nil]
      end
    end

    def parse_date(date_str)
      # Parse dates like "July 13th 2024", "May 24th 2023"
      cleaned = date_str.gsub(/(\d+)(st|nd|rd|th)/, '\1')
      Time.parse(cleaned)
    rescue ArgumentError
      nil
    end

    def detect_series_type(tags)
      tags_lower = tags.map(&:downcase)
      return "manhwa" if tags_lower.any? { |t| t.include?("manhwa") || t.include?("korean") }
      return "manhua" if tags_lower.any? { |t| t.include?("manhua") || t.include?("chinese") }
      return "manga" if tags_lower.any? { |t| t.include?("manga") || t.include?("japanese") }

      "manhwa" # Default for AsuraScans (primarily Korean webtoons)
    end
  end
end

# Register with legacy namespace
module Scrapers
  module AsuraScans
    Adapter = ::AsuraScans::Adapter
  end
end
