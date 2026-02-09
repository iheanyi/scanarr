# frozen_string_literal: true

require "nokogiri"

# MangaFreak adapter (ww2.mangafreak.me)
# Pure HTML scraping — search, series details, chapters, and page images
#
# URL patterns:
#   Search:   /Find/{query_with_underscores}
#   Series:   /Manga/{Series_Slug}
#   Chapters: /Read1_{Series_Slug}_{Number}
#   Latest:   /Latest_Releases/{page}
#
# Domain history: mangafreak.net → w13.mangafreak.net → ww2.mangafreak.me
module MangaFreak
  class Adapter < ::BaseAdapter
    BASE_URL = "https://ww2.mangafreak.me"

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest]
    end

    # Browse latest releases with pagination
    def browse(sort: "latest", page: 1, limit: 20)
      url = "#{base_url}/Latest_Releases/#{page}"
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      doc.css(".latest_releases_item").map do |item|
        parse_latest_release_item(item)
      end.compact
    rescue StandardError => e
      Rails.logger.error "[MangaFreak] Browse error: #{e.message}"
      []
    end

    def search(query)
      normalized = query.strip.gsub(/\s+/, "_")
      url = "#{base_url}/Find/#{normalized}"
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      doc.css(".manga_search_item").map do |item|
        parse_search_item(item)
      end.compact
    rescue StandardError => e
      Rails.logger.error "[MangaFreak] Search error: #{e.message}"
      []
    end

    def series(id_or_url)
      url = normalize_series_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      data = doc.at_css(".manga_series_data")
      return nil unless data

      title = data.at_css("h1")&.text&.strip

      # Cover image
      cover = doc.at_css(".manga_series_image img")&.[]("src")

      # Extract metadata from divs
      alt_title = extract_field_text(data, "Alternative Title:")
      alt_titles = alt_title ? alt_title.split(/[;,]/).map(&:strip).reject(&:empty?) : []

      status_text = extract_field_text(data, "ON-GOING") ? "ongoing" : nil
      status_text ||= extract_field_text(data, "COMPLETED") ? "completed" : nil
      status_text ||= "ongoing"

      author = extract_field_text(data, "Written By:")
      artist = extract_field_text(data, "Illustrated By:")

      # Series type from reading direction
      # "Left to Right" = manhwa/webtoon, "Right to Left" = manga
      type_text = extract_field_text(data, "Type:")
      series_type = type_text&.match?(/Left.*to.*Right/i) ? "manhwa" : "manga"

      # Genres
      tags = data.css(".series_sub_genre_list a").map { |a| a.text.strip }

      # Description
      description = doc.at_css(".manga_series_description p")&.text&.strip

      # Extract slug as ID
      slug = url.split("/Manga/").last&.chomp("/")

      ResultTypes::Series.new(
        id: slug,
        title: title,
        alt_titles: alt_titles,
        description: description,
        author: author,
        artist: artist,
        status: status_text,
        tags: tags,
        series_type: series_type,
        cover_url: cover,
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[MangaFreak] Series error: #{e.message}"
      nil
    end

    def chapters(series_url)
      url = normalize_series_url(series_url)
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      rows = doc.css(".manga_series_list table tr")

      rows.filter_map do |row|
        link = row.at_css("td a")
        next unless link

        href = link["href"]
        chapter_text = link.text.strip
        date_td = row.css("td")[1]
        published_at = parse_date(date_td&.text&.strip)

        # Extract chapter number and title from text like "Chapter 1 - Romance Dawn"
        number, title = parse_chapter_text(chapter_text)
        next unless number

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::Chapter.new(
          id: href.split("/").last,
          title: title,
          number: number,
          volume: nil,
          language: "en",
          group: "MangaFreak",
          published_at: published_at,
          url: full_url
        )
      end.sort_by { |ch| ch.number.to_f }
    rescue StandardError => e
      Rails.logger.error "[MangaFreak] Chapters error: #{e.message}"
      []
    end

    def pages(chapter_url)
      url = chapter_url.start_with?("http") ? chapter_url : "#{base_url}#{chapter_url}"
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      # Pages use img#gohere with src pointing to images.mangafreak.me
      images = doc.css("img#gohere[src]")

      # Fallback: look for images in the reading container
      images = doc.css(".read_img img[src], .manga_page img[src]") if images.empty?

      images.each_with_index.filter_map do |img, idx|
        src = img["src"]
        next unless src && src.match?(/\.(jpg|jpeg|png|webp|gif)/i)

        ResultTypes::Page.new(
          index: idx,
          url: src,
          mime_type: guess_mime_type(src)
        )
      end
    rescue StandardError => e
      Rails.logger.error "[MangaFreak] Pages error: #{e.message}"
      []
    end

    private

    def base_url
      config["base_url"] || BASE_URL
    end

    def normalize_series_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      else
        "#{base_url}/Manga/#{id_or_url}"
      end
    end

    def parse_search_item(item)
      link = item.at_css("h3 a") || item.at_css("a[href*='/Manga/']")
      return nil unless link

      href = link["href"]
      title = link.text.strip
      img = item.at_css("img")
      cover_url = img&.[]("src")

      slug = href.split("/Manga/").last&.chomp("/")

      ResultTypes::SearchResult.new(
        id: slug,
        title: title,
        url: href.start_with?("http") ? href : "#{base_url}#{href}",
        cover_url: cover_url,
        author: nil
      )
    end

    def parse_latest_release_item(item)
      manga_link = item.at_css(".latest_releases_info a[href*='/Manga/']")
      return nil unless manga_link

      href = manga_link["href"]
      title = manga_link.text.strip
      img = item.at_css(".latest_releases_image img")
      cover_url = img&.[]("src")
      time_text = item.at_css(".latest_releases_time")&.text&.strip

      slug = href.split("/Manga/").last&.chomp("/")

      # Determine status from CSS class
      image_div = item.at_css(".latest_releases_image")
      status = if image_div&.[]("class")&.include?("completed")
        "completed"
      else
        "ongoing"
      end

      ResultTypes::BrowseResult.new(
        id: slug,
        title: title,
        url: href.start_with?("http") ? href : "#{base_url}#{href}",
        cover_url: cover_url,
        language: "en",
        author: nil,
        status: status,
        last_updated: time_text,
        chapter_count: nil,
        description: nil
      )
    end

    # Extract text from a div containing the given label
    # e.g., "Written By: Oda, Eiichiro" → "Oda, Eiichiro"
    def extract_field_text(container, label)
      container.css("div").each do |div|
        text = div.text.strip
        if text.include?(label)
          return text.sub(/.*#{Regexp.escape(label)}\s*/, "").strip.presence
        end
      end
      nil
    end

    # Parse "Chapter 1 - Romance Dawn" → ["1", "Romance Dawn"]
    # Parse "Chapter 1173" → ["1173", nil]
    # Parse "Chapter 12.5 - Extra" → ["12.5", "Extra"]
    def parse_chapter_text(text)
      match = text.match(/Chapter\s+(\d+(?:\.\d+)?)\s*(?:-\s*(.+))?/i)
      return nil unless match

      [ match[1], match[2]&.strip&.presence ]
    end

    def parse_date(text)
      return nil if text.blank?
      Date.strptime(text, "%Y/%m/%d")
    rescue Date::Error
      nil
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
  module MangaFreak
    Adapter = ::MangaFreak::Adapter
  end
end
