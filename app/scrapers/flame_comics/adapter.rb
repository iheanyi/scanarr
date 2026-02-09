# frozen_string_literal: true

require "json"
require "nokogiri"

# FlameComics adapter (formerly Flame Scans / Luminous Scans)
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/flamecomics
#
# Next.js app — all data comes via /_next/data/{buildId}/{path}.json
# Build ID must be fetched dynamically from __NEXT_DATA__ script tag.
# Rate limit: strict, 2 requests per 7 seconds (delay_ms: 3500)
module Scrapers
  module FlameComics
    class Adapter < Scrapers::BaseAdapter
      BASE_URL = "https://flamecomics.xyz"
      CDN_URL = "https://cdn.flamecomics.xyz"

      STATUS_MAP = {
        "ongoing" => "ongoing",
        "completed" => "completed",
        "hiatus" => "hiatus",
        "dropped" => "cancelled"
      }.freeze

      def supports_browse?
        true
      end

      def browse_sort_options
        %w[latest popular alphabetical]
      end

      def search(query)
        all_series = fetch_all_series
        return [] if all_series.empty?

        query_normalized = query.downcase.gsub(/[^a-z0-9 ]/, "")

        all_series.select do |s|
          titles = [ s["title"] ] + (s["altTitles"] || [])
          titles.any? { |t| t.to_s.downcase.gsub(/[^a-z0-9 ]/, "").include?(query_normalized) }
        end.map { |s| search_result_from(s) }
      rescue StandardError => e
        Rails.logger.error "[FlameComics] Search error: #{e.message}"
        []
      end

      def series(id_or_url)
        series_id = extract_series_id(id_or_url)
        data = fetch_series_data(series_id)
        return nil unless data

        series_data = data.dig("pageProps", "series")
        return nil unless series_data

        description = series_data["description"]
        description = Nokogiri::HTML.fragment(description).text if description.present?

        ResultTypes::Series.new(
          id: series_id.to_s,
          title: series_data["title"],
          alt_titles: series_data["altTitles"] || [],
          description: description,
          author: Array(series_data["author"]).first,
          artist: Array(series_data["artist"]).first,
          status: STATUS_MAP.fetch(series_data["status"]&.downcase, "ongoing"),
          tags: series_data["tags"] || [],
          series_type: (series_data["type"] || "manga").downcase,
          cover_url: cover_url(series_id, series_data["cover"], series_data["last_edit"]),
          url: "#{base_url}/series/#{series_id}"
        )
      rescue StandardError => e
        Rails.logger.error "[FlameComics] Series error: #{e.message}"
        nil
      end

      def chapters(series_url)
        series_id = extract_series_id(series_url)
        data = fetch_series_data(series_id)
        return [] unless data

        chapters_data = data.dig("pageProps", "chapters") || []

        chapters_data.map do |ch|
          chapter_number = ch["chapter"]
          published_at = ch["release_date"] ? Time.at(ch["release_date"]).utc.iso8601 : nil

          ResultTypes::Chapter.new(
            id: ch["token"],
            title: ch["title"].presence,
            number: format_chapter_number(chapter_number),
            volume: nil,
            language: "en",
            group: "Flame Comics",
            published_at: published_at,
            url: "#{base_url}/series/#{series_id}/#{ch["token"]}"
          )
        end.sort_by { |ch| ch.number.to_f }
      rescue StandardError => e
        Rails.logger.error "[FlameComics] Chapters error: #{e.message}"
        []
      end

      def pages(chapter_url)
        series_id, token = extract_chapter_parts(chapter_url)
        return [] unless series_id && token

        data = fetch_page_data(series_id, token)
        return [] unless data

        chapter_data = data.dig("pageProps", "chapter")
        return [] unless chapter_data

        images = chapter_data["images"] || {}
        release_date = chapter_data["release_date"]

        images.sort_by { |k, _| k.to_i }.map do |_key, value|
          page_name = value["name"]
          ResultTypes::Page.new(
            index: _key.to_i,
            url: page_image_url(series_id, token, page_name, release_date),
            mime_type: guess_mime_type(page_name)
          )
        end
      rescue StandardError => e
        Rails.logger.error "[FlameComics] Pages error: #{e.message}"
        []
      end

      def browse(sort: "latest", page: 1, limit: 20)
        case sort
        when "popular"
          browse_popular(page: page, limit: limit)
        when "alphabetical"
          browse_alphabetical(page: page, limit: limit)
        else # "latest"
          browse_latest(page: page, limit: limit)
        end
      rescue StandardError => e
        Rails.logger.error "[FlameComics] Browse error: #{e.message}"
        []
      end

      private

      def base_url
        config.fetch("base_url", BASE_URL)
      end

      # --- Build ID management ---

      def fetch_build_id
        @build_id ||= fetch_build_id_from_page
      end

      def fetch_build_id_from_page(url = base_url)
        response = http.get(url)
        extract_build_id(response.body)
      end

      def extract_build_id(html)
        doc = Nokogiri::HTML(html)
        script = doc.at_css("script#__NEXT_DATA__")
        return nil unless script

        data = JSON.parse(script.text)
        data["buildId"]
      rescue JSON::ParserError
        nil
      end

      def reset_build_id!
        @build_id = nil
      end

      # Fetch JSON from Next.js data endpoint, handling stale build ID
      def next_data_get(path, params: {})
        build_id = fetch_build_id
        return nil unless build_id

        url = "#{base_url}/_next/data/#{build_id}/#{path}.json"
        response = http.get(url, params: params)

        # If we get a 404 HTML response, the build ID is stale
        if response.status == 404 || (response.headers["content-type"]&.include?("text/html") && response.status != 200)
          reset_build_id!
          new_build_id = extract_build_id(response.body) || fetch_build_id_from_page
          @build_id = new_build_id
          return nil unless new_build_id

          url = "#{base_url}/_next/data/#{new_build_id}/#{path}.json"
          response = http.get(url, params: params)
        end

        return nil unless response.status == 200

        JSON.parse(response.body)
      rescue JSON::ParserError
        nil
      end

      # --- Data fetching ---

      def fetch_all_series
        data = next_data_get("browse")
        data&.dig("pageProps", "series") || []
      end

      def fetch_series_data(series_id)
        next_data_get("series/#{series_id}", params: { id: series_id })
      end

      def fetch_page_data(series_id, token)
        next_data_get("series/#{series_id}/#{token}", params: { id: series_id, token: token })
      end

      # --- URL helpers ---

      def cover_url(series_id, cover, last_edit = nil)
        return nil unless cover
        url = "#{CDN_URL}/uploads/images/series/#{series_id}/#{cover}"
        url += "?#{last_edit}" if last_edit
        url
      end

      def page_image_url(series_id, token, page_name, release_date = nil)
        url = "#{CDN_URL}/uploads/images/series/#{series_id}/#{token}/#{page_name}"
        url += "?#{release_date}" if release_date
        url
      end

      # --- ID extraction ---

      def extract_series_id(id_or_url)
        url = id_or_url.to_s

        # Handle full URLs: https://flamecomics.xyz/series/42 or /series/42/token
        if url.include?("/series/")
          parts = url.split("/series/").last.split("/")
          return parts.first
        end

        # Already an ID
        url
      end

      def extract_chapter_parts(chapter_url)
        url = chapter_url.to_s

        if url.include?("/series/")
          parts = url.split("/series/").last.split("/")
          return [ parts[0], parts[1] ] if parts.size >= 2
        end

        [ nil, nil ]
      end

      # --- Result builders ---

      def search_result_from(series_data)
        series_id = series_data["series_id"]
        ResultTypes::SearchResult.new(
          id: series_id.to_s,
          title: series_data["title"],
          url: "#{base_url}/series/#{series_id}",
          cover_url: cover_url(series_id, series_data["cover"], series_data["last_edit"]),
          language: "en",
          author: Array(series_data["author"]).first
        )
      end

      def browse_result_from(series_data)
        series_id = series_data["series_id"]
        ResultTypes::BrowseResult.new(
          id: series_id.to_s,
          title: series_data["title"],
          url: "#{base_url}/series/#{series_id}",
          cover_url: cover_url(series_id, series_data["cover"], series_data["last_edit"]),
          language: "en",
          author: Array(series_data["author"]).first,
          status: STATUS_MAP.fetch(series_data["status"]&.downcase, nil),
          last_updated: series_data["last_edit"] ? Time.at(series_data["last_edit"]).utc : nil,
          chapter_count: nil,
          description: series_data["description"]
        )
      end

      # --- Browse helpers ---

      def browse_popular(page: 1, limit: 20)
        all_series = fetch_all_series
        sorted = all_series.sort_by { |s| -(s["views"] || 0) }
        paginate(sorted, page: page, limit: limit).map { |s| browse_result_from(s) }
      end

      def browse_latest(page: 1, limit: 20)
        all_series = fetch_all_series
        sorted = all_series.sort_by { |s| -(s["last_edit"] || 0) }
        paginate(sorted, page: page, limit: limit).map { |s| browse_result_from(s) }
      end

      def browse_alphabetical(page: 1, limit: 20)
        all_series = fetch_all_series
        sorted = all_series.sort_by { |s| s["title"].to_s.downcase }
        paginate(sorted, page: page, limit: limit).map { |s| browse_result_from(s) }
      end

      def paginate(items, page: 1, limit: 20)
        offset = (page - 1) * limit
        items[offset, limit] || []
      end

      # --- Utility ---

      def format_chapter_number(number)
        return "0" if number.nil?
        # If it's a whole number, return as integer string; otherwise keep decimal
        number.to_f == number.to_f.floor ? number.to_i.to_s : number.to_s
      end

      def guess_mime_type(filename)
        case filename.to_s.downcase
        when /\.png/ then "image/png"
        when /\.gif/ then "image/gif"
        when /\.webp/ then "image/webp"
        else "image/jpeg"
        end
      end
    end
  end

end
