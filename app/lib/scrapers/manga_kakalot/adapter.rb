# frozen_string_literal: true

require "json"
require "nokogiri"

# MangaKakalot adapter (mangakakalot.gg)
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/mangakakalot
#
# Hybrid source: JSON API for chapters, HTML scraping for search/series, JS extraction for pages.
# Domain history: mangakakalot.com -> manganelo.com -> readmanganato.com -> chapmanganato.to -> mangakakalot.gg
module Scrapers
  module MangaKakalot
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://www.mangakakalot.gg"

    # Vietnamese diacritical character mapping for query normalization
    VIETNAMESE_MAP = {
      "\u00E0" => "a", "\u00E1" => "a", "\u1EA1" => "a", "\u1EA3" => "a", "\u00E3" => "a",
      "\u00E2" => "a", "\u1EA7" => "a", "\u1EA5" => "a", "\u1EAD" => "a", "\u1EA9" => "a", "\u1EAB" => "a",
      "\u0103" => "a", "\u1EB1" => "a", "\u1EAF" => "a", "\u1EB7" => "a", "\u1EB3" => "a", "\u1EB5" => "a",
      "\u00E8" => "e", "\u00E9" => "e", "\u1EB9" => "e", "\u1EBB" => "e", "\u1EBD" => "e",
      "\u00EA" => "e", "\u1EC1" => "e", "\u1EBF" => "e", "\u1EC7" => "e", "\u1EC3" => "e", "\u1EC5" => "e",
      "\u00EC" => "i", "\u00ED" => "i", "\u1ECB" => "i", "\u1EC9" => "i", "\u0129" => "i",
      "\u00F2" => "o", "\u00F3" => "o", "\u1ECD" => "o", "\u1ECF" => "o", "\u00F5" => "o",
      "\u00F4" => "o", "\u1ED3" => "o", "\u1ED1" => "o", "\u1ED9" => "o", "\u1ED5" => "o", "\u1ED7" => "o",
      "\u01A1" => "o", "\u1EDD" => "o", "\u1EDB" => "o", "\u1EE3" => "o", "\u1EDF" => "o", "\u1EE1" => "o",
      "\u00F9" => "u", "\u00FA" => "u", "\u1EE5" => "u", "\u1EE7" => "u", "\u0169" => "u",
      "\u01B0" => "u", "\u1EEB" => "u", "\u1EE9" => "u", "\u1EF1" => "u", "\u1EED" => "u", "\u1EEF" => "u",
      "\u1EF3" => "y", "\u00FD" => "y", "\u1EF5" => "y", "\u1EF7" => "y", "\u1EF9" => "y",
      "\u0111" => "d"
    }.freeze

    SPECIAL_CHARS = /[!@%^*()+={}\[\]<>?\/,.:;'"&#~\-$|\\_ ]+/

    def supports_browse?
      true
    end

    def browse_sort_options
      %w[latest popular]
    end

    def search(query, filters: {})
      _ = filters
      normalized = normalize_query(query)
      response = http.get("#{base_url}/search/story/#{normalized}")
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      items = doc.css(".panel_story_list .story_item, div.list-truyen-item-wrap, div.list-comic-item-wrap")

      items.filter_map do |item|
        link = item.at_css("h3 a") || item.at_css("a")
        next unless link

        href = link["href"]
        title = link.text.strip
        img = item.at_css("img")
        cover = img&.[]("src") || img&.[]("data-src")

        next unless title.present? && href.present?

        ResultTypes::SearchResult.new(
          id: extract_slug(href),
          title: title,
          url: absolute_url(href),
          cover_url: cover,
          author: nil
        )
      end
    rescue StandardError => e
      Rails.logger.error "[MangaKakalot] Search error: #{e.message}"
      []
    end

    def series(id_or_url)
      url = normalize_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      slug = extract_slug(url)

      title = doc.at_css("div.manga-info-top h1, div.panel-story-info h1, h1")&.text&.strip

      cover = doc.at_css("div.manga-info-pic img, span.info-image img")
      cover_url = cover&.[]("src") || cover&.[]("data-src")

      author = extract_table_value(doc, "author")
      status = extract_table_value(doc, "status")

      genres = doc.css("div.manga-info-top li:last-child a, td.table-value a[href*='genre']").map { |a| a.text.strip }
      genres = genres.reject { |g| g.downcase == "manga" || g.blank? }

      description = doc.at_css("div#noidungm, div#panel-story-info-description, div#contentBox")&.text&.strip

      alt_el = doc.at_css(".story-alternative, tr:has(.info-alternative) h2")
      alt_titles = alt_el ? alt_el.text.split(/[;,]/).map(&:strip).reject(&:empty?) : []

      ResultTypes::Series.new(
        id: slug,
        title: title,
        alt_titles: alt_titles,
        description: description,
        author: author,
        artist: extract_table_value(doc, "artist"),
        status: normalize_status(status),
        tags: genres,
        series_type: detect_series_type(genres),
        cover_url: cover_url,
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[MangaKakalot] Series error: #{e.message}"
      nil
    end

    def chapters(series_url)
      slug = extract_slug(normalize_url(series_url))
      all_chapters = []
      offset = 0
      limit = 1000

      loop do
        response = http.get("#{base_url}/api/manga/#{slug}/chapters", params: { limit: limit, offset: offset })
        return all_chapters unless response.status == 200

        data = JSON.parse(response.body)
        chapter_list = data.dig("data", "chapters") || []
        break if chapter_list.empty?

        chapter_list.each do |ch|
          chapter_name = ch["chapter_name"]
          chapter_slug = ch["chapter_slug"]
          chapter_num = ch["chapter_num"]
          updated_at = ch["updated_at"]

          # Build a display title from chapter_name minus the number prefix
          title = chapter_name&.sub(/\A\s*Chapter\s+[\d.]+\s*[-:]?\s*/i, "")&.strip
          title = nil if title.blank?

          all_chapters << ResultTypes::Chapter.new(
            id: chapter_slug,
            title: title,
            number: format_chapter_number(chapter_num),
            volume: nil,
            language: "en",
            group: "MangaKakalot",
            published_at: parse_date(updated_at),
            url: "#{base_url}/manga/#{slug}/#{chapter_slug}"
          )
        end

        break unless data.dig("data", "pagination", "has_more")
        offset += limit
      end

      all_chapters.sort_by { |ch| ch.number.to_f }
    rescue StandardError => e
      Rails.logger.error "[MangaKakalot] Chapters error: #{e.message}"
      []
    end

    def pages(chapter_url)
      response = http.get(chapter_url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)

      # Extract JS variables from script tags
      script_content = doc.css("script").map(&:text).join("\n")
      cdns = extract_js_array(script_content, "cdns") + extract_js_array(script_content, "backupImage")
      images = extract_js_array(script_content, "chapterImages")

      if images.any? && cdns.any?
        cdn = cdns.first
        images.each_with_index.map do |image_path, idx|
          url = image_path.start_with?("http") ? image_path : "#{cdn}#{image_path}"
          ResultTypes::Page.new(
            index: idx + 1,
            url: url,
            mime_type: guess_mime_type(url)
          )
        end
      else
        # Fallback: extract images from reader container
        doc.css("div.container-chapter-reader > img").each_with_index.filter_map do |img, idx|
          src = img["src"] || img["data-src"]
          next unless src.present?

          ResultTypes::Page.new(
            index: idx + 1,
            url: src,
            mime_type: guess_mime_type(src)
          )
        end
      end
    rescue StandardError => e
      Rails.logger.error "[MangaKakalot] Pages error: #{e.message}"
      []
    end

    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = filters
      path = case sort.to_s.downcase
      when "popular"
               "/manga-list/hot-manga"
      else
               "/manga-list/latest-manga"
      end

      response = http.get("#{base_url}#{path}", params: { page: page })
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      items = doc.css("div.truyen-list > div.list-truyen-item-wrap, div.comic-list > .list-comic-item-wrap")

      items.filter_map do |item|
        link = item.at_css("h3 a") || item.at_css("a")
        next unless link

        href = link["href"]
        title = link.text.strip
        img = item.at_css("img")
        cover = img&.[]("src") || img&.[]("data-src")

        next unless title.present? && href.present?

        ResultTypes::BrowseResult.new(
          id: extract_slug(href),
          title: title,
          url: absolute_url(href),
          cover_url: cover,
          language: "en",
          author: nil,
          status: nil,
          last_updated: nil,
          chapter_count: nil,
          description: nil
        )
      end
    rescue StandardError => e
      Rails.logger.error "[MangaKakalot] Browse error: #{e.message}"
      []
    end

    private

    def base_url
      config.fetch("base_url", BASE_URL)
    end

    def normalize_query(query)
      result = query.downcase
      VIETNAMESE_MAP.each { |from, to| result = result.gsub(from, to) }
      result = result.gsub(SPECIAL_CHARS, "_")
      result = result.squeeze("_")
      result = result.sub(/\A_+/, "").sub(/_+\z/, "")
      result
    end

    def normalize_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.include?("/")
        "#{base_url}/#{id_or_url}"
      else
        "#{base_url}/manga/#{id_or_url}"
      end
    end

    def absolute_url(href)
      href.start_with?("http") ? href : "#{base_url}#{href}"
    end

    def extract_slug(url_or_path)
      path = url_or_path.sub(%r{\Ahttps?://[^/]+}, "")
      path.sub(%r{\A/manga/}, "").split("/").first
    end

    def extract_table_value(doc, label)
      # Pattern 1: li containing label text
      li = doc.css("li, td").find { |el| el.text.downcase.include?("#{label}") && el.at_css("a") }
      if li
        value = li.css("a").map { |a| a.text.strip }.join(", ")
        return value if value.present?
      end

      # Pattern 2: td:containsOwn(label) + td
      doc.css("tr").each do |row|
        label_cell = row.at_css("td.table-label, td:first-child")
        next unless label_cell&.text&.downcase&.include?(label)
        value_cell = row.at_css("td.table-value, td:last-child")
        if value_cell
          links = value_cell.css("a")
          return links.any? ? links.map { |a| a.text.strip }.join(", ") : value_cell.text.strip
        end
      end

      nil
    end

    def extract_js_array(content, var_name)
      match = content.match(/var\s+#{Regexp.escape(var_name)}\s*=\s*(\[.*?\]);/m)
      return [] unless match
      JSON.parse(match[1])
    rescue JSON::ParserError
      []
    end

    def format_chapter_number(num)
      return "0" if num.nil?
      num == num.to_i ? num.to_i.to_s : num.to_s
    end

    def parse_date(date_str)
      return nil if date_str.blank?
      Time.parse(date_str)
    rescue ArgumentError
      nil
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
