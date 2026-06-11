# frozen_string_literal: true

# MangaPill adapter
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/mangapill
#
# Browse limitations:
# - No pagination support (homepage only shows ~40 latest, ~10 trending)
# - Only "latest" and "popular" sort options (no alphabetical)
# - The `page` and `limit` parameters are ignored due to homepage constraints
module Scrapers
  module MangaPill
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://mangapill.com"

    # MangaPill supports browse via homepage scraping
    def supports_browse?
      true
    end

    # Available sort options (no alphabetical - not supported by source)
    def browse_sort_options
      %w[latest popular]
    end

    # Browse the homepage for latest updates or trending manga
    # Note: Pagination is not supported - MangaPill homepage is a single page
    # @param sort [String] "latest" for new chapters, "popular" for trending
    # @param page [Integer] Ignored (no pagination support)
    # @param limit [Integer] Ignored (returns all available from homepage)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = filters
      response = http.get(base_url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      case sort.to_s.downcase
      when "popular"
        parse_trending_manga(doc)
      else # "latest" is default
        parse_latest_chapters(doc)
      end
    rescue StandardError => e
      Rails.logger.error "[MangaPill] Browse error: #{e.message}"
      []
    end

    def search(query, filters: {})
      _ = filters
      # MangaPill uses a simple search query param
      encoded_query = CGI.escape(query)
      response = http.get("#{base_url}/search", params: { q: encoded_query })
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
          url: "#{base_url}#{href}",
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
        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"
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
          url: src.start_with?("http") ? src : "#{base_url}#{src}",
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
            url: src.start_with?("http") ? src : "#{base_url}#{src}",
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

    # Parse "New Chapters" section from homepage
    # Structure: Each card has chapter link, cover image, and manga link with title
    # Card structure:
    #   a[href*='/chapters/'] > figure > img (cover)
    #   a[href*='/chapters/'] > div (chapter number like #55)
    #   a[href^='/manga/'] > div.line-clamp-2.font-bold (title)
    def parse_latest_chapters(doc)
      results = []
      seen_ids = Set.new

      # Find the "New Chapters" grid - it's nested inside .grid > div
      # The actual cards are in a nested grid
      chapter_cards = doc.css("a[href*='/chapters/']")

      chapter_cards.each do |chapter_link|
        # Find the parent card container
        card = chapter_link.parent
        next unless card

        # Find the manga link in the same card
        manga_link = card.css("a[href^='/manga/']").first
        next unless manga_link

        href = manga_link["href"]
        manga_id = extract_manga_id(href)
        next unless manga_id
        next if seen_ids.include?(manga_id) # Deduplicate

        seen_ids << manga_id

        # Cover image is in the chapter link's figure
        img = chapter_link.css("img").first || card.css("img").first

        # Title is in the manga link, specifically in div.line-clamp-2 or div.font-bold
        title_el = manga_link.css("div.line-clamp-2").first || manga_link.css("div").first
        title = title_el&.text&.strip

        next unless title.present?

        # Extract chapter number from chapter link
        chapter_num = extract_chapter_number(chapter_link["href"]) || extract_chapter_number(chapter_link.text)

        results << ResultTypes::BrowseResult.new(
          id: manga_id,
          title: title,
          url: "#{base_url}#{href}",
          cover_url: img&.[]("data-src") || img&.[]("src"),
          language: "en",
          author: nil,
          status: nil,
          last_updated: nil,
          chapter_count: chapter_num&.to_i,
          description: nil
        )
      end

      results
    end

    # Parse "Trending Mangas" section from homepage
    # Structure: Cards with cover, title, and metadata tags (type, year, status)
    # Card structure:
    #   a[href^='/manga/'] > figure > img (cover)
    #   a[href^='/manga/'] > div.line-clamp-2 (title)
    #   div.flex-wrap with tags showing type/year/status
    def parse_trending_manga(doc)
      results = []
      seen_ids = Set.new

      # Find the "Trending Mangas" heading and navigate to its grid container
      trending_heading = doc.css("h4").find { |h| h.text.downcase.include?("trending") }
      return results unless trending_heading

      # The grid is a sibling in the grandparent container
      # Navigate: heading -> parent div -> parent div -> find the grid with manga cards
      grandparent = trending_heading.parent&.parent
      return results unless grandparent

      # The trending grid has class pattern like "grid ... grid-cols-2"
      trending_grid = grandparent.css("div.grid").find do |grid|
        grid["class"]&.include?("grid-cols") && grid.css("a[href^='/manga/']").any?
      end
      return results unless trending_grid

      # Get direct children of the grid (the card containers)
      trending_grid.children.select(&:element?).each do |card|
        manga_link = card.css("a[href^='/manga/']").first
        next unless manga_link

        href = manga_link["href"]
        manga_id = extract_manga_id(href)
        next unless manga_id
        next if seen_ids.include?(manga_id)

        seen_ids << manga_id

        # Cover image is in the link's figure
        img = manga_link.css("img").first || card.css("img").first

        # Title is in div.line-clamp-2 or div.font-black inside the link
        title_el = manga_link.css("div.line-clamp-2").first ||
                   manga_link.css("div.font-black").first ||
                   card.css("div.line-clamp-2").first
        title = title_el&.text&.strip

        next unless title.present?

        # Extract status from the tags (look for publishing/finished/etc)
        status = nil
        card.css("div.bg-card").each do |tag|
          tag_text = tag.text.strip.downcase
          if %w[publishing finished hiatus discontinued].include?(tag_text)
            status = normalize_status(tag_text)
            break
          end
        end

        results << ResultTypes::BrowseResult.new(
          id: manga_id,
          title: title,
          url: "#{base_url}#{href}",
          cover_url: img&.[]("data-src") || img&.[]("src"),
          language: "en",
          author: nil,
          status: status,
          last_updated: nil,
          chapter_count: nil,
          description: nil
        )
      end

      results
    end

    # Extract manga ID from URL path like "/manga/123/series-name"
    def extract_manga_id(path)
      return nil unless path
      # URL format: /manga/123/series-name -> extract "123/series-name"
      match = path.match(%r{/manga/(.+)})
      match ? match[1] : nil
    end

    def normalize_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.include?("/")
        "#{base_url}/manga/#{id_or_url}"
      else
        "#{base_url}/manga/#{id_or_url}"
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
  end
  end
end
