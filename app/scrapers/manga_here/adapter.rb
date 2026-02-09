# frozen_string_literal: true

require "json"
require "nokogiri"
require "cgi"
require "date"

# MangaHere adapter (mangahere.cc)
# Reference: https://github.com/keiyoushi/extensions-source (mangahere extension)
#
# MangaHere is a long-running manga aggregator using HTML scraping.
# Search, series, and chapter listing are straightforward HTML parsing.
# Page image extraction requires decoding Dean Edwards packed JavaScript
# from chapterfun.ashx AJAX responses.
#
# Domain history: mangahere.com -> mangahere.cc (current)
module Scrapers
  module MangaHere
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://www.mangahere.cc"

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    # Browse the directory for latest updates or popular manga
    # @param sort [String] "latest" or "popular"
    # @param page [Integer] Page number (1-indexed)
    # @param limit [Integer] Ignored (uses site default)
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20)
      path = case sort.to_s.downcase
             when "latest"
               "/directory/#{page}.htm?latest"
             else
               "/directory/#{page}.htm"
             end

      response = http.get("#{base_url}#{path}", headers: default_headers)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_browse_results(doc)
    rescue StandardError => e
      Rails.logger.error "[MangaHere] Browse error: #{e.message}"
      []
    end

    # Search for manga by title
    # @param query [String] Search term
    # @return [Array<ResultTypes::SearchResult>]
    def search(query)
      response = http.get(
        "#{base_url}/search",
        params: { title: query, page: 1, stype: 1 },
        headers: default_headers
      )
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_search_results(doc)
    rescue StandardError => e
      Rails.logger.error "[MangaHere] Search error: #{e.message}"
      []
    end

    # Fetch series details
    # @param id_or_url [String] Series slug, path, or full URL
    # @return [ResultTypes::Series, nil]
    def series(id_or_url)
      url = normalize_url(id_or_url)
      response = http.get(url, headers: default_headers)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      title = doc.at_css("span.detail-info-right-title-font")&.text&.strip
      return nil unless title.present?

      author = doc.css(".detail-info-right-say > a").map { |a| a.text.strip }.reject(&:empty?).first
      status_text = doc.at_css("span.detail-info-right-title-tip")&.text&.strip
      description = doc.at_css(".fullcontent")&.text&.strip
      cover = doc.at_css("img.detail-info-cover-img")&.[]("src")
      cover = normalize_image_url(cover) if cover

      genres = doc.css(".detail-info-right-tag-list > a").map { |a| a.text.strip }.reject(&:empty?)

      slug = extract_slug(url)

      ResultTypes::Series.new(
        id: slug,
        title: title,
        alt_titles: [],
        description: description,
        author: author,
        artist: nil,
        status: normalize_status(status_text),
        tags: genres,
        series_type: detect_series_type(genres),
        cover_url: cover,
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[MangaHere] Series error: #{e.message}"
      nil
    end

    # Fetch chapter list for a series
    # @param series_url [String] Series URL or slug
    # @return [Array<ResultTypes::Chapter>]
    def chapters(series_url)
      url = normalize_url(series_url)
      response = http.get(url, headers: default_headers)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      parse_chapter_list(doc)
    rescue StandardError => e
      Rails.logger.error "[MangaHere] Chapters error: #{e.message}"
      []
    end

    # Fetch page image URLs for a chapter
    # Uses two strategies:
    # 1. Webtoon mode: Extract packed JS with newImgs array from the chapter page
    # 2. Page-by-page mode: Fetch chapterfun.ashx for each page and decode packed JS
    #
    # @param chapter_url [String] Chapter URL
    # @return [Array<ResultTypes::Page>]
    def pages(chapter_url)
      url = chapter_url.start_with?("http") ? chapter_url : "#{base_url}#{chapter_url}"
      response = http.get(url, headers: default_headers)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      body = response.body

      # Check for webtoon/long-strip reader mode
      if doc.at_css("script[src*='chapter_bar']")
        return extract_webtoon_pages(body)
      end

      # Page-by-page mode: extract chapter metadata then fetch each page
      extract_paged_images(doc, body, url)
    rescue StandardError => e
      Rails.logger.error "[MangaHere] Pages error: #{e.message}"
      []
    end

    private

    def base_url
      config["base_url"] || BASE_URL
    end

    def default_headers
      { "Cookie" => "isAdult=1" }
    end

    def normalize_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.start_with?("/")
        "#{base_url}#{id_or_url}"
      else
        "#{base_url}/manga/#{id_or_url}/"
      end
    end

    def normalize_image_url(url)
      return nil unless url
      return "https:#{url}" if url.start_with?("//")
      return url if url.start_with?("http")
      "#{base_url}#{url}"
    end

    def extract_slug(url)
      match = url.match(%r{/manga/([^/]+)})
      match ? match[1] : url.split("/").last
    end

    # --- Browse parsing ---

    def parse_browse_results(doc)
      results = []

      doc.css(".manga-list-1-list li").each do |li|
        link = li.at_css("a")
        next unless link

        href = link["href"]
        title = link["title"]&.strip
        next unless title.present? && href.present?

        img = li.at_css("img.manga-list-1-cover")
        cover = img&.[]("src")
        cover = normalize_image_url(cover) if cover

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        results << ResultTypes::BrowseResult.new(
          id: extract_slug(href),
          title: title,
          url: full_url,
          cover_url: cover,
          language: "en",
          author: nil,
          status: nil,
          last_updated: nil,
          chapter_count: nil,
          description: nil
        )
      end

      results
    end

    # --- Search parsing ---

    def parse_search_results(doc)
      results = []

      doc.css(".manga-list-4-list > li").each do |li|
        link = li.at_css(".manga-list-4-item-title > a")
        next unless link

        href = link["href"]
        title = link["title"]&.strip || link.text.strip
        next unless title.present? && href.present?

        img = li.at_css("img.manga-list-4-cover")
        cover = img&.[]("src")
        cover = normalize_image_url(cover) if cover

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        results << ResultTypes::SearchResult.new(
          id: extract_slug(href),
          title: title,
          url: full_url,
          cover_url: cover,
          author: nil
        )
      end

      results
    end

    # --- Chapter parsing ---

    def parse_chapter_list(doc)
      chapters = []

      doc.css("ul.detail-main-list > li").each do |li|
        link = li.at_css("a")
        next unless link

        href = link["href"]
        next unless href.present?

        title_el = link.at_css("p.title3")
        chapter_text = title_el&.text&.strip || ""

        date_el = link.at_css("p.title2")
        date_text = date_el&.text&.strip

        chapter_num = extract_chapter_number(chapter_text)
        volume = extract_volume_number(chapter_text)
        chapter_title = extract_chapter_title(chapter_text)

        full_url = href.start_with?("http") ? href : "#{base_url}#{href}"

        chapters << ResultTypes::Chapter.new(
          id: href.split("/").reject(&:empty?).last(2).join("/"),
          title: chapter_title,
          number: chapter_num || "0",
          volume: volume,
          language: "en",
          group: "MangaHere",
          published_at: parse_date(date_text),
          url: full_url
        )
      end

      chapters.uniq { |ch| ch.number }.sort_by { |ch| ch.number.to_f }
    end

    def extract_chapter_number(text)
      return nil unless text
      match = text.match(/c(\d+(?:\.\d+)?)/i)
      return match[1] if match
      match = text.match(/ch(?:apter)?[.\s]*(\d+(?:\.\d+)?)/i)
      match&.[](1)
    end

    def extract_volume_number(text)
      return nil unless text
      match = text.match(/v(?:ol(?:ume)?)?[.\s]*(\d+)/i)
      match&.[](1)
    end

    def extract_chapter_title(text)
      return nil unless text
      # Remove vol/chapter markers, keep remaining title
      cleaned = text.gsub(/Vol\.\d+\s*/i, "").gsub(/Ch?\.\d+(?:\.\d+)?\s*/i, "").strip
      cleaned.presence
    end

    def parse_date(text)
      return nil unless text.present?

      case text
      when /today/i, /ago/i
        Date.today
      when /yesterday/i
        Date.today - 1
      else
        Date.strptime(text, "%b %d,%Y") rescue nil
      end
    end

    # --- Page image extraction ---

    # Webtoon mode: images are in a packed JS script on the page
    def extract_webtoon_pages(body)
      images = []

      # Find the packed script containing newImgs
      packed = body.match(/eval\(function\(p,a,c,k,e,d\)\{.*?\}(?:\(.*?\))\)/m)
      return [] unless packed

      decoded = unpack_dean_edwards(packed[0])
      return [] unless decoded

      # Extract newImgs array
      img_match = decoded.match(/newImgs\s*=\s*\[([^\]]+)\]/)
      return [] unless img_match

      urls = img_match[1].scan(/"([^"]+)"/)
      urls.flatten.each_with_index do |url, idx|
        full_url = normalize_image_url(url)
        images << ResultTypes::Page.new(
          index: idx,
          url: full_url,
          mime_type: guess_mime_type(full_url)
        )
      end

      images
    end

    # Page-by-page mode: fetch chapterfun.ashx for each page
    def extract_paged_images(doc, body, chapter_url)
      images = []

      # Extract chapter ID
      cid_match = body.match(/var\s+chapterid\s*=\s*(\d+)/)
      return [] unless cid_match
      chapter_id = cid_match[1]

      # Extract secret key from packed JS
      secret_key = extract_secret_key(body)

      # Get total page count from pager
      page_count = extract_page_count(doc)
      return [] if page_count.zero?

      # Build base URL for chapterfun.ashx requests
      # Chapter URL: /manga/slug/v01/c001/1.html -> base: /manga/slug/v01/c001/
      chapter_base = chapter_url.sub(/\d+\.html.*$/, "")

      page_count.times do |i|
        page_num = i + 1
        image_url = fetch_page_image(chapter_base, chapter_id, page_num, secret_key, chapter_url)
        next unless image_url

        images << ResultTypes::Page.new(
          index: i,
          url: image_url,
          mime_type: guess_mime_type(image_url)
        )
      end

      images
    end

    # Extract the secret key (dm5_key) from packed JS on the chapter page
    def extract_secret_key(body)
      packed = body.scan(/eval\(function\(p,a,c,k,e,d\)\{.*?\}(?:\([^)]*\))\)/m)
      packed.each do |script|
        decoded = unpack_dean_edwards(script)
        next unless decoded
        key_match = decoded.match(/var\s+dm5_key\s*=\s*"([^"]*)"/)
        return key_match[1] if key_match
      end
      ""
    end

    # Get total page count from the pager navigation
    def extract_page_count(doc)
      # The pager has page links; the second-to-last <a> has the total count
      pager = doc.at_css(".pager-list-left > span")
      return 0 unless pager

      links = pager.css("a")
      return 0 if links.size < 2

      # Second-to-last link has data-page or text with page count
      page_link = links[-2]
      count = page_link["data-page"]&.to_i || page_link.text.strip.to_i
      count.positive? ? count : 0
    end

    # Fetch a single page image URL from chapterfun.ashx
    def fetch_page_image(chapter_base, chapter_id, page_num, secret_key, referer)
      ajax_url = "#{chapter_base}chapterfun.ashx"
      ajax_headers = default_headers.merge(
        "Referer" => referer,
        "Accept" => "*/*",
        "X-Requested-With" => "XMLHttpRequest"
      )

      # Try with key first, then without
      [ secret_key, "" ].each do |key|
        response = http.get(
          ajax_url,
          params: { cid: chapter_id, page: page_num, key: key },
          headers: ajax_headers
        )
        next unless response.status == 200 && response.body.present?

        decoded = unpack_dean_edwards(response.body)
        next unless decoded

        # Extract pix (base path) and pvalue (filename)
        pix_match = decoded.match(/pix\s*=\s*"([^"]+)"/)
        pvalue_match = decoded.match(/pvalue\s*=\s*\[([^\]]+)\]/)
        next unless pix_match && pvalue_match

        pix = pix_match[1]
        # pvalue is an array, take the first (current page) image
        pvalue = pvalue_match[1].scan(/"([^"]+)"/).flatten.first
        next unless pvalue

        return normalize_image_url("#{pix}#{pvalue}")
      end

      nil
    rescue StandardError => e
      Rails.logger.error "[MangaHere] Page image fetch error (page #{page_num}): #{e.message}"
      nil
    end

    # --- Dean Edwards JavaScript Unpacker ---
    # Decodes the common eval(function(p,a,c,k,e,d){...}) obfuscation pattern.
    # This is a pure Ruby implementation — no JS runtime needed.

    def unpack_dean_edwards(packed_js)
      # Extract the encoded payload arguments: p, a, c, k, e, d
      match = packed_js.match(
        /eval\(function\(p,a,c,k,e,d\)\{.*?\}\('(.+)',(\d+),(\d+),'([^']*)'\.split\('\|'\)/m
      )
      return nil unless match

      payload = match[1]
      radix = match[2].to_i
      count = match[3].to_i
      keywords = match[4].split("|")

      # Replace encoded tokens in the payload with their keyword values
      # Tokens are word-boundary sequences of alphanumeric chars interpreted in the given radix
      payload.gsub(/\b(\w+)\b/) do |word|
        index = unbase(word, radix)
        if index < keywords.length && keywords[index].present?
          keywords[index]
        else
          word
        end
      end
    rescue StandardError
      nil
    end

    # Convert a string representation in the given radix to an integer
    def unbase(str, radix)
      if radix <= 36
        str.to_i(radix)
      else
        # For radix > 36, use extended encoding (0-9, a-z, A-Z, then special chars)
        result = 0
        str.each_char do |c|
          result = result * radix + char_to_value(c)
        end
        result
      end
    end

    def char_to_value(c)
      case c
      when "0".."9" then c.ord - "0".ord
      when "a".."z" then c.ord - "a".ord + 10
      when "A".."Z" then c.ord - "A".ord + 36
      else 62
      end
    end

    # --- Utility methods ---

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
