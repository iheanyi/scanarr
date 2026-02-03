# frozen_string_literal: true

# MangaPill adapter
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/mangapill
module MangaPill
  class Adapter < ::BaseAdapter
    BASE_URL = "https://mangapill.com"

    def search(query)
      # MangaPill uses a simple search query param
      encoded_query = CGI.escape(query)
      response = http.get("#{BASE_URL}/search", params: { q: encoded_query })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      doc.css(".grid > div").map do |card|
        link = card.css("a").first
        next unless link

        href = link["href"]
        img = card.css("img").first
        title = card.css("a > div").last&.text&.strip

        next unless title && href

        ResultTypes::SearchResult.new(
          id: href.split("/").last,
          title: title,
          url: "#{BASE_URL}#{href}",
          cover_url: img&.[]("data-src") || img&.[]("src"),
          author: nil
        )
      end.compact
    rescue StandardError => e
      Rails.logger.error "[MangaPill] Search error: #{e.message}"
      []
    end

    def series(id_or_url)
      url = normalize_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      # Title from h1 or first large heading
      title = doc.css("h1").first&.text&.strip

      # Cover from main image
      cover = doc.css("img[data-src]").first&.[]("data-src")
      cover ||= doc.css("figure img, .manga-cover img").first&.[]("src")

      # Description from summary section
      description = doc.css("[class*='summary'], [class*='description'], p.text--secondary").first&.text&.strip

      # Extract metadata from info rows
      author = extract_info_value(doc, "Author")
      status = extract_info_value(doc, "Status")
      series_type = extract_info_value(doc, "Type")

      # Alternative titles
      alt_titles = []
      alt_title_el = doc.css("[class*='alt'], h2.text--secondary").first
      if alt_title_el
        alt_titles = alt_title_el.text.split(/[;,]/).map(&:strip).reject(&:empty?)
      end

      ResultTypes::Series.new(
        id: url.split("/").last(2).join("/"),
        title: title,
        alt_titles: alt_titles,
        description: description,
        author: author,
        artist: extract_info_value(doc, "Artist"),
        status: normalize_status(status),
        tags: extract_genres(doc),
        series_type: series_type&.downcase || "manga",
        cover_url: cover,
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[MangaPill] Series error: #{e.message}"
      nil
    end

    def chapters(series_url)
      url = normalize_url(series_url)
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      # Chapters are in anchor tags with href containing /chapters/
      chapter_links = doc.css("a[href*='/chapters/']")

      chapter_links.map do |link|
        href = link["href"]
        full_url = href.start_with?("http") ? href : "#{BASE_URL}#{href}"
        chapter_text = link.text.strip

        # Extract chapter number from text or URL
        # URL format: /chapters/manga_id-chapter_number/series-name-chapter-X
        chapter_num = extract_chapter_number(href) || extract_chapter_number(chapter_text)

        ResultTypes::Chapter.new(
          id: href.split("/").last,
          title: chapter_text.gsub(/chapter\s*\d+/i, "").strip.presence,
          number: chapter_num || "0",
          volume: nil,
          language: "en",
          group: "MangaPill",
          published_at: nil,
          url: full_url
        )
      end.uniq { |ch| ch.number }.sort_by { |ch| ch.number.to_f }
    rescue StandardError => e
      Rails.logger.error "[MangaPill] Chapters error: #{e.message}"
      []
    end

    def pages(chapter_url)
      response = http.get(chapter_url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      images = []

      # MangaPill uses img tags with data-src for lazy loading
      doc.css("img[data-src]").each_with_index do |img, idx|
        src = img["data-src"]
        next unless src && looks_like_page_url?(src)

        images << ResultTypes::Page.new(
          index: idx,
          url: src.start_with?("http") ? src : "#{BASE_URL}#{src}",
          mime_type: guess_mime_type(src)
        )
      end

      # Fallback: check chapter content div for images
      if images.empty?
        doc.css(".container img, [id*='reader'] img, [class*='reader'] img").each_with_index do |img, idx|
          src = img["src"] || img["data-src"]
          next unless src && looks_like_page_url?(src)

          images << ResultTypes::Page.new(
            index: idx,
            url: src.start_with?("http") ? src : "#{BASE_URL}#{src}",
            mime_type: guess_mime_type(src)
          )
        end
      end

      images
    rescue StandardError => e
      Rails.logger.error "[MangaPill] Pages error: #{e.message}"
      []
    end

    private

    def normalize_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.include?("/")
        "#{BASE_URL}/manga/#{id_or_url}"
      else
        "#{BASE_URL}/manga/#{id_or_url}"
      end
    end

    def extract_info_value(doc, label)
      # Look for label text followed by value
      doc.css("div, span, p").each do |el|
        text = el.text
        if text =~ /#{label}[:\s]+(.+)/i
          return Regexp.last_match(1).strip
        end
      end
      nil
    end

    def extract_genres(doc)
      genres = []
      doc.css("a[href*='/genre/'], a[href*='/tag/']").each do |link|
        genres << link.text.strip
      end
      genres.uniq
    end

    def extract_chapter_number(text)
      return nil unless text
      # Match chapter number patterns
      # URL: /chapters/2-11117000/one-piece-chapter-1117
      # Text: "Chapter 1117"
      match = text.match(/chapter[- ]?(\d+(?:\.\d+)?)/i)
      return match[1] if match

      # URL pattern: manga_id-chapter_num000
      match = text.match(/-(\d+)000\//)
      return match[1].sub(/^0+/, "") if match

      nil
    end

    def looks_like_page_url?(url)
      # Filter out logos, avatars, icons, etc.
      return false if url.nil?
      return false if url.include?("logo")
      return false if url.include?("avatar")
      return false if url.include?("icon")
      return false if url.include?("favicon")
      return false if url =~ /\d+x\d+/ && url =~ /avatar|thumb|small/i

      # Must have image extension or be from CDN
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

    def normalize_status(status)
      case status&.downcase
      when /ongoing/, /publishing/ then "ongoing"
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
  module MangaPill
    Adapter = ::MangaPill::Adapter
  end
end
