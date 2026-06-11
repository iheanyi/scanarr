# frozen_string_literal: true

require "json"
require "nokogiri"

# MangaBuddy adapter (mangabuddy.com)
# Reference: keiyoushi/extensions-source MadTheme multi-source
#
# MangaBuddy uses the MadTheme CMS framework, which provides:
# - HTML search with `.book-detailed-item` result cards
# - Series details at `/manga/{id}-{slug}` with `.detail` section
# - Chapter list via `#chapter-list > li` or API at `/api/manga/{id}/chapters`
# - Page images via JS variables `mainServer` + `chapImages`, or HTML `#chapter-images img`
#
# CDN image fallback: sb.mbcdn.xyz when primary CDN returns errors
module Scrapers
  module MangaBuddy
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://mangabuddy.com"

    MANGA_ID_REGEX = %r{/manga/(\d+)-}
    CHAPTER_ID_REGEX = /chapterId\s*=\s*(\d+)/

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
    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = filters
      sort_param = sort.to_s.downcase == "popular" ? "views" : "updated_at"
      response = http.get("#{base_url}/search", params: { sort: sort_param, page: page.to_s })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_search_items(doc).map do |result|
        ResultTypes::BrowseResult.new(
          id: result.id,
          title: result.title,
          url: result.url,
          cover_url: result.cover_url,
          language: "en",
          author: result.author,
          status: nil,
          last_updated: nil,
          chapter_count: nil,
          description: nil
        )
      end
    rescue StandardError => e
      Rails.logger.error "[MangaBuddy] Browse error: #{e.message}"
      []
    end

    # Search for manga by title
    # @param query [String] Search term
    # @return [Array<ResultTypes::SearchResult>]
    def search(query, filters: {})
      _ = filters
      response = http.get("#{base_url}/search", params: { q: query, page: "1" })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_search_items(doc)
    rescue StandardError => e
      Rails.logger.error "[MangaBuddy] Search error: #{e.message}"
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

      title = doc.at_css(".detail h1")&.text&.strip
      return nil unless title.present?

      author = doc.css(".detail .meta > p > strong:contains('Authors') ~ a, .detail .meta > p > strong:contains('Author') ~ a")
        .map { |a| a.text.strip.delete(",").strip }
        .reject(&:empty?)
        .first

      artist = doc.css(".detail .meta > p > strong:contains('Artist') ~ a")
        .map { |a| a.text.strip.delete(",").strip }
        .reject(&:empty?)
        .first

      genres = doc.css(".detail .meta > p > strong:contains('Genres') ~ a")
        .map { |a| a.text.strip.delete(",").strip }
        .reject(&:empty?)

      cover_img = doc.at_css("#cover img")
      cover_url = cover_img&.[]("data-src") || cover_img&.[]("src")

      alt_title = doc.at_css(".detail h2")&.text&.strip
      alt_titles = alt_title ? alt_title.split(/[;,]/).map(&:strip).reject(&:empty?) : []

      description_parts = doc.css(".summary .content, .summary .content ~ p")
      description = description_parts.map(&:text).join(" ").strip.presence

      status_text = doc.at_css(".detail .meta > p > strong:contains('Status') ~ a")&.text&.strip

      ResultTypes::Series.new(
        id: extract_manga_id(url) || url.split("/").last,
        title: title,
        alt_titles: alt_titles,
        description: description,
        author: author,
        artist: artist,
        status: normalize_status(status_text),
        tags: genres,
        series_type: detect_series_type(genres),
        cover_url: normalize_image_url(cover_url),
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[MangaBuddy] Series error: #{e.message}"
      nil
    end

    # Fetch chapter list for a series
    # @param series_url [String] Series URL or ID
    # @return [Array<ResultTypes::Chapter>]
    def chapters(series_url)
      url = normalize_series_url(series_url)
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      # Extract bookId and bookSlug from embedded script
      script = doc.css("script:contains('bookId')").first
      book_id = nil
      book_slug = nil
      if script
        script_text = script.text
        book_id = script_text[/bookId\s*=\s*(\d+)/, 1]
        book_slug = script_text[/bookSlug\s*=\s*"([^"]+)"/, 1]
      end

      # Parse chapters from HTML
      chapter_list = parse_chapter_elements(doc)

      # Check if there's a "show more" button requiring API fetch
      show_more = doc.at_css("div#show-more-chapters > span")
      if show_more && (book_id || book_slug)
        api_id = book_slug || book_id
        api_response = http.get("#{base_url}/api/manga/#{api_id}/chapters", params: { source: "detail" })
        if api_response.status == 200
          api_doc = Nokogiri::HTML(api_response.body)
          api_chapters = parse_chapter_elements(api_doc)

          unless api_chapters.empty?
            # Merge: keep HTML chapters that aren't in the API response, then append API chapters
            api_urls = api_chapters.map(&:url).to_set
            unique_html = chapter_list.reject { |ch| api_urls.include?(ch.url) }
            chapter_list = unique_html + api_chapters
          end
        end
      end

      chapter_list.sort_by { |ch| ch.number.to_f }
    rescue StandardError => e
      Rails.logger.error "[MangaBuddy] Chapters error: #{e.message}"
      []
    end

    # Fetch page image URLs for a chapter
    # @param chapter_url [String] Chapter URL
    # @return [Array<ResultTypes::Page>]
    def pages(chapter_url)
      url = chapter_url.start_with?("http") ? chapter_url : "#{base_url}#{chapter_url}"
      response = http.get(url)
      return [] unless response.status == 200

      body = response.body

      # Try the chapterServer API approach first
      manga_id = body[MANGA_ID_REGEX, 1] || url[MANGA_ID_REGEX, 1]
      chapter_id = body[CHAPTER_ID_REGEX, 1]

      if manga_id && chapter_id
        server_response = http.get(
          "#{base_url}/service/backend/chapterServer/",
          params: { server_id: "1", chapter_id: chapter_id }
        )
        body = server_response.body if server_response.status == 200
      end

      # Method 1: mainServer + chapImages JS variables
      if body.include?("var mainServer = \"")
        main_server = body[/var mainServer = "([^"]*)"/, 1]
        chap_images_str = body[/var chapImages = '([^']*)'/, 1]

        if main_server && chap_images_str
          scheme_prefix = main_server.start_with?("//") ? "https:" : ""
          chap_images = chap_images_str.split(",")

          return chap_images.each_with_index.map do |path, idx|
            image_url = "#{scheme_prefix}#{main_server}#{path}"
            ResultTypes::Page.new(
              index: idx,
              url: image_url,
              mime_type: guess_mime_type(image_url)
            )
          end
        end
      end

      # Method 2: chapImages JS variable with full URLs
      if body.include?("var chapImages = '")
        chap_images_str = body[/var chapImages = '([^']*)'/, 1]
        if chap_images_str
          chap_images = chap_images_str.split(",")
          if chap_images.all? { |img| img.start_with?("http://") || img.start_with?("https://") }
            return chap_images.each_with_index.map do |img_url, idx|
              ResultTypes::Page.new(
                index: idx,
                url: img_url,
                mime_type: guess_mime_type(img_url)
              )
            end
          end
        end
      end

      # Method 3: HTML img tags fallback
      doc = Nokogiri::HTML(body)
      images = doc.css("#chapter-images img, .chapter-image[data-src]")
      images.each_with_index.map do |img, idx|
        src = img["data-src"] || img["src"]
        next unless src.present?

        ResultTypes::Page.new(
          index: idx,
          url: normalize_image_url(src),
          mime_type: guess_mime_type(src)
        )
      end.compact
    rescue StandardError => e
      Rails.logger.error "[MangaBuddy] Pages error: #{e.message}"
      []
    end

    private

    # Parse search result items from MadTheme `.book-detailed-item` cards
    def parse_search_items(doc)
      doc.css(".book-detailed-item").map do |item|
        link = item.at_css("a")
        next unless link

        href = link["abs:href"] || link["href"]
        title = link["title"] || link.text.strip
        next unless title.present? && href.present?

        img = item.at_css("img")
        cover_url = img&.[]("data-src") || img&.[]("src")

        summary = item.at_css(".summary")&.text&.strip

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::SearchResult.new(
          id: extract_manga_id(href) || href.split("/").last,
          title: title,
          url: full_url,
          cover_url: normalize_image_url(cover_url),
          author: nil
        )
      end.compact
    end

    # Parse chapter elements from `#chapter-list > li`
    def parse_chapter_elements(doc)
      doc.css("#chapter-list > li").map do |li|
        link = li.at_css("a")
        next unless link

        href = link["href"]
        next unless href.present?

        chapter_title_el = li.at_css(".chapter-title")
        chapter_title = chapter_title_el&.text&.strip || link.text.strip

        date_text = li.at_css(".chapter-update")&.text&.strip
        published_at = parse_chapter_date(date_text)

        # Extract chapter number from title
        chapter_num = extract_chapter_number(chapter_title)

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        ResultTypes::Chapter.new(
          id: href.split("/").last,
          title: clean_chapter_title(chapter_title, chapter_num),
          number: chapter_num || "0",
          volume: nil,
          language: "en",
          group: nil,
          published_at: published_at,
          url: full_url
        )
      end.compact
    end

    # Normalize a series URL from various input formats
    def normalize_series_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.start_with?("/")
        "#{base_url}#{id_or_url}"
      else
        "#{base_url}/manga/#{id_or_url}"
      end
    end

    # Extract manga numeric ID from URL path like "/manga/123-series-name"
    def extract_manga_id(url_or_path)
      match = url_or_path.to_s.match(MANGA_ID_REGEX)
      match ? match[1] : nil
    end

    # Extract chapter number from title text
    def extract_chapter_number(text)
      return nil unless text

      match = text.match(/chapter[- ]?(\d+(?:\.\d+)?)/i)
      return match[1] if match

      match = text.match(/ch(?:ap)?[.\s-]*(\d+(?:\.\d+)?)/i)
      return match[1] if match

      nil
    end

    # Remove the "Chapter N" prefix from title to get the descriptive part
    def clean_chapter_title(full_title, chapter_num)
      return nil unless full_title.present?

      cleaned = full_title
        .gsub(/chapter\s*\d+(?:\.\d+)?[:\s-]*/i, "")
        .strip

      cleaned.presence
    end

    # Parse chapter date strings (MadTheme format)
    # Handles "MMM dd, yyyy" and relative dates like "3 hours ago"
    def parse_chapter_date(date_str)
      return nil unless date_str.present?

      if date_str.include?("ago")
        parse_relative_date(date_str)
      else
        Date.strptime(date_str, "%b %d, %Y").to_time
      end
    rescue StandardError
      nil
    end

    # Parse relative date strings like "3 hours ago", "2 days ago"
    def parse_relative_date(date_str)
      number = date_str[/(\d+)/, 1]&.to_i
      return nil unless number

      case date_str
      when /year/   then number.years.ago
      when /month/  then number.months.ago
      when /day/    then number.days.ago
      when /hour/   then number.hours.ago
      when /minute/ then number.minutes.ago
      when /second/ then number.seconds.ago
      end
    end

    # Normalize image URL to absolute
    def normalize_image_url(url)
      return nil unless url
      return url if url.start_with?("http")
      return "https:#{url}" if url.start_with?("//")
      "#{base_url}#{url}"
    end

    def detect_series_type(tags)
      tags_lower = (tags || []).map(&:downcase)
      return "manhwa" if tags_lower.any? { |t| t.include?("manhwa") || t.include?("korean") }
      return "manhua" if tags_lower.any? { |t| t.include?("manhua") || t.include?("chinese") }
      "manga"
    end

    def guess_mime_type(url)
      case url.to_s.downcase
      when /\.png/ then "image/png"
      when /\.gif/ then "image/gif"
      when /\.webp/ then "image/webp"
      else "image/jpeg"
      end
    end
  end
  end
end
