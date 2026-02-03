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

        ResultTypes::SearchResult.new(
          id: href.split("/").last,
          title: title,
          url: href.start_with?("http") ? href : "#{BASE_URL}#{href}",
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

      title = doc.css("h1, h2").first&.text&.strip
      cover = doc.css("img[alt*='poster'], img[alt*='cover']").first&.[]("src")
      description = doc.css("[class*='description'], [class*='summary']").first&.text&.strip

      # Extract metadata
      info_section = doc.css("[class*='info'], [class*='detail']").first
      author = extract_text_after(info_section, "Author")
      artist = extract_text_after(info_section, "Artist")
      status = extract_text_after(info_section, "Status")

      ResultTypes::Series.new(
        id: url.split("/").last,
        title: title,
        alt_titles: [],
        description: description,
        author: author,
        artist: artist,
        status: normalize_status(status),
        tags: [],
        series_type: "manhwa",
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

      # Chapters are in links with chapter in href
      chapter_links = doc.css("a[href*='chapter']").select { |a| a["href"]&.include?("/chapter-") }

      chapter_links.map do |link|
        href = link["href"]
        full_url = href.start_with?("http") ? href : "#{BASE_URL}#{href}"

        # Extract chapter number from URL or text
        chapter_num = extract_chapter_number(href) || extract_chapter_number(link.text)
        title_text = link.text.strip

        # Check for premium/locked chapters
        is_locked = link.css("[class*='lock']").any? || title_text.include?("🔒")

        ResultTypes::Chapter.new(
          id: href.split("/").last,
          title: is_locked ? "🔒 #{title_text}" : title_text,
          number: chapter_num || "0",
          volume: nil,
          language: "en",
          group: "Asura Scans",
          published_at: nil,
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
  end
end

# Register with legacy namespace
module Scrapers
  module AsuraScans
    Adapter = ::AsuraScans::Adapter
  end
end
