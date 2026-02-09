# frozen_string_literal: true

require "json"

# ZeroScans adapter (zscans.com, formerly zeroscans.com)
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/zeroscans
#
# ZeroScans is an English scanlation group hosting manhwa/manga.
# Uses a JSON API at /swordflake/ for all data.
# The /swordflake/comics endpoint returns all comics at once, so search
# and browse are handled client-side by filtering/sorting the full list.
#
# Domain history: zeroscans.com -> zscans.com
module Scrapers
  module ZeroScans
    class Adapter < Scrapers::BaseAdapter
      BASE_URL = "https://zscans.com"
      API_PATH = "swordflake"

      def supports_browse?
        true
      end

      def browse_sort_options
        %w[latest popular alphabetical]
      end

      # Browse comics with sorting and pagination
      # @param sort [String] "latest", "popular", or "alphabetical"
      # @param page [Integer] Page number (1-indexed)
      # @param limit [Integer] Results per page (default 20)
      # @return [Array<ResultTypes::BrowseResult>]
      def browse(sort: "latest", page: 1, limit: 20)
        comics = fetch_comics_data
        return [] if comics.empty?

        sorted = case sort.to_s.downcase
                 when "popular"
                   comics.sort_by { |c| -(c["view_count"] || 0) }
                 when "alphabetical"
                   comics.sort_by { |c| (c["name"] || "").downcase }
                 else # latest — sort by most recently updated (highest ID as proxy)
                   comics.sort_by { |c| -(c["id"] || 0) }
                 end

        paginated = sorted.each_slice(limit).to_a
        current_page = paginated[page - 1] || []

        current_page.map { |comic| comic_to_browse_result(comic) }
      rescue StandardError => e
        Rails.logger.error "[ZeroScans] Browse error: #{e.message}"
        []
      end

      # Search comics by name (client-side filtering of full catalog)
      # @param query [String] Search term
      # @return [Array<ResultTypes::SearchResult>]
      def search(query)
        comics = fetch_comics_data
        return [] if comics.empty?

        filtered = comics.select { |c| (c["name"] || "").downcase.include?(query.downcase) }

        filtered.map { |comic| comic_to_search_result(comic) }
      rescue StandardError => e
        Rails.logger.error "[ZeroScans] Search error: #{e.message}"
        []
      end

      # Fetch series details by slug or URL
      # @param id_or_url [String] Series slug, ID, or full URL
      # @return [ResultTypes::Series, nil]
      def series(id_or_url)
        slug = extract_slug(id_or_url)
        comic_id = extract_comic_id(id_or_url)

        comics = fetch_comics_data
        return nil if comics.empty?

        # Find by slug first, then by ID
        comic = comics.find { |c| c["slug"] == slug }
        comic ||= comics.find { |c| c["id"].to_s == comic_id.to_s } if comic_id

        return nil unless comic

        comic_to_series(comic)
      rescue StandardError => e
        Rails.logger.error "[ZeroScans] Series error: #{e.message}"
        nil
      end

      # Fetch chapter list for a series
      # @param series_url [String] Series URL or slug
      # @return [Array<ResultTypes::Chapter>]
      def chapters(series_url)
        comic_id = extract_comic_id(series_url)
        slug = extract_slug(series_url)

        # If we don't have the ID from the URL, look it up from the comics list
        if comic_id.nil?
          comics = fetch_comics_data
          comic = comics.find { |c| c["slug"] == slug }
          return [] unless comic
          comic_id = comic["id"]
        end

        all_chapters = []
        page = 1

        loop do
          response = http.get("#{base_url}/#{API_PATH}/comic/#{comic_id}/chapters", params: { sort: "desc", page: page })
          break unless response.status == 200

          data = parse_json(response.body)
          break unless data

          page_data = data.dig("data", "data") || []
          break if page_data.empty?

          all_chapters.concat(page_data)

          current_page = data.dig("data", "current_page") || page
          last_page = data.dig("data", "last_page") || page
          break if current_page >= last_page

          page += 1
        end

        all_chapters.map { |ch| chapter_to_result(ch, slug) }
          .sort_by { |ch| ch.number.to_f }
      rescue StandardError => e
        Rails.logger.error "[ZeroScans] Chapters error: #{e.message}"
        []
      end

      # Fetch page image URLs for a chapter
      # @param chapter_url [String] Chapter URL like /comics/{slug}/{chapter_id}
      # @return [Array<ResultTypes::Page>]
      def pages(chapter_url)
        slug = extract_slug(chapter_url)
        chapter_id = chapter_url.split("/").last

        response = http.get("#{base_url}/#{API_PATH}/comic/#{slug}/chapters/#{chapter_id}")
        return [] unless response.status == 200

        data = parse_json(response.body)
        return [] unless data

        chapter_data = data.dig("data", "chapter") || {}

        # Prefer high quality, fall back to good quality
        image_urls = chapter_data["high_quality"]
        image_urls = chapter_data["good_quality"] if image_urls.nil? || image_urls.empty?
        return [] if image_urls.nil? || image_urls.empty?

        image_urls.each_with_index.map do |url, idx|
          ResultTypes::Page.new(
            index: idx,
            url: url,
            mime_type: guess_mime_type(url)
          )
        end
      rescue StandardError => e
        Rails.logger.error "[ZeroScans] Pages error: #{e.message}"
        []
      end

      private

      def base_url
        config["base_url"] || BASE_URL
      end

      # Fetch the full comics catalog from the API
      # @return [Array<Hash>] List of comic data hashes
      def fetch_comics_data
        response = http.get("#{base_url}/#{API_PATH}/comics")
        return [] unless response.status == 200

        data = parse_json(response.body)
        return [] unless data

        data.dig("data", "comics") || []
      end

      def parse_json(body)
        JSON.parse(body)
      rescue JSON::ParserError => e
        Rails.logger.error "[ZeroScans] JSON parse error: #{e.message}"
        nil
      end

      # Extract the series slug from a URL or string
      # URL format: /comics/{slug}?id={id} or https://zscans.com/comics/{slug}?id={id}
      def extract_slug(url_or_id)
        if url_or_id.include?("/comics/")
          # Extract slug from URL path, strip query params
          path = url_or_id.split("/comics/").last
          path.split("?").first.split("/").first
        elsif url_or_id.include?("/")
          url_or_id.split("/").last.split("?").first
        else
          url_or_id
        end
      end

      # Extract the comic ID from a URL query parameter
      # URL format: /comics/{slug}?id={id}
      def extract_comic_id(url_or_id)
        match = url_or_id.match(/[?&]id=(\d+)/)
        return match[1] if match

        # If it's just a bare numeric string
        return url_or_id if url_or_id.match?(/^\d+$/)

        nil
      end

      # Build the series URL with slug and ID
      def build_series_url(comic)
        "#{base_url}/comics/#{comic["slug"]}?id=#{comic["id"]}"
      end

      # Get the best available cover URL from the cover object
      def extract_cover_url(comic)
        cover = comic["cover"]
        return nil unless cover.is_a?(Hash)

        # Prefer full > horizontal > vertical
        url = cover["full"]
        if url.blank?
          url = cover["horizontal"]&.sub("-horizontal", "-full")
        end
        if url.blank?
          url = cover["vertical"]&.sub("-vertical", "-full")
        end
        if url.blank?
          url = cover["horizontal"] || cover["vertical"]
        end

        url.presence
      end

      # Normalize status from ZeroScans status objects
      # Status IDs: 1=New, 2=Ongoing(?), 3=Completed, 4=Dropped, 5=Ongoing, 6=On Hiatus
      def normalize_zs_status(statuses)
        return "ongoing" unless statuses.is_a?(Array) && statuses.any?

        status_ids = statuses.map { |s| s["id"] }

        return "completed" if status_ids.include?(3)
        return "hiatus" if status_ids.include?(6)
        return "cancelled" if status_ids.include?(4)
        return "ongoing" if status_ids.include?(5) || status_ids.include?(2)

        "ongoing"
      end

      # Parse relative date strings like "3 hours ago", "2 days ago"
      def parse_relative_date(date_str)
        return nil if date_str.blank?

        parts = date_str.strip.split(" ")
        return nil if parts.size < 2

        value = parts[0].to_i
        unit = parts[1].sub(/s$/, "") # Remove plural "s"

        case unit
        when "sec" then Time.current - value.seconds
        when "min" then Time.current - value.minutes
        when "hour" then Time.current - value.hours
        when "day" then Time.current - value.days
        when "week" then Time.current - value.weeks
        when "month" then Time.current - value.months
        when "year" then Time.current - value.years
        end
      rescue StandardError
        nil
      end

      def comic_to_search_result(comic)
        ResultTypes::SearchResult.new(
          id: comic["slug"],
          title: comic["name"],
          url: build_series_url(comic),
          cover_url: extract_cover_url(comic),
          author: nil
        )
      end

      def comic_to_browse_result(comic)
        ResultTypes::BrowseResult.new(
          id: comic["slug"],
          title: comic["name"],
          url: build_series_url(comic),
          cover_url: extract_cover_url(comic),
          language: "en",
          author: nil,
          status: normalize_zs_status(comic["statuses"]),
          last_updated: nil,
          chapter_count: comic["chapter_count"],
          description: comic["summary"]
        )
      end

      def comic_to_series(comic)
        genres = (comic["genres"] || []).map { |g| g["name"] }

        ResultTypes::Series.new(
          id: comic["slug"],
          title: comic["name"],
          alt_titles: [],
          description: comic["summary"],
          author: nil,
          artist: nil,
          status: normalize_zs_status(comic["statuses"]),
          tags: genres,
          series_type: detect_series_type(genres),
          cover_url: extract_cover_url(comic),
          url: build_series_url(comic)
        )
      end

      def chapter_to_result(chapter, series_slug)
        ResultTypes::Chapter.new(
          id: chapter["id"].to_s,
          title: nil,
          number: chapter["name"].to_s,
          volume: nil,
          language: "en",
          group: chapter["group"],
          published_at: parse_relative_date(chapter["created_at"]),
          url: "#{base_url}/comics/#{series_slug}/#{chapter["id"]}"
        )
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
