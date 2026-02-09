# frozen_string_literal: true

# MangaSee adapter
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/mangasee
module Scrapers
  module MangaSee
    class Adapter < Scrapers::BaseAdapter
      BASE_URL = "https://mangasee123.com"

      def search(query)
        # MangaSee uses a JSON directory for search
        response = http.get("#{BASE_URL}/_search.php")
        return [] unless response.status == 200

        directory = JSON.parse(response.body)

        # Filter by query (case-insensitive)
        query_lower = query.downcase
        matches = directory.select do |entry|
          entry["s"]&.downcase&.include?(query_lower) ||
            entry["al"]&.any? { |alt| alt.downcase.include?(query_lower) }
        end

        matches.first(20).map do |entry|
          ResultTypes::SearchResult.new(
            id: entry["i"],
            title: entry["s"],
            url: "#{BASE_URL}/manga/#{entry['i']}",
            cover_url: "https://temp.compsci88.com/cover/#{entry['i']}.jpg",
            author: entry["a"]&.join(", ")
          )
        end
      rescue JSON::ParserError, StandardError => e
        Rails.logger.error "[MangaSee] Search error: #{e.message}"
        []
      end

      def series(id_or_url)
        slug = extract_slug(id_or_url)
        response = http.get("#{BASE_URL}/manga/#{slug}")
        return nil unless response.status == 200

        doc = Nokogiri::HTML(response.body)

        title = doc.css(".MainContainer h1").text.strip
        cover_url = "https://temp.compsci88.com/cover/#{slug}.jpg"

        # Extract metadata from the info box
        info_items = doc.css(".list-group-item")
        author = extract_info(info_items, "Author")
        artist = extract_info(info_items, "Artist")
        status = extract_info(info_items, "Status")
        description = doc.css(".Content").first&.text&.strip

        ResultTypes::Series.new(
          id: slug,
          title: title,
          alt_titles: [],
          description: description,
          author: author,
          artist: artist,
          status: normalize_status(status),
          tags: [],
          series_type: "manga",
          cover_url: cover_url,
          url: "#{BASE_URL}/manga/#{slug}"
        )
      rescue StandardError => e
        Rails.logger.error "[MangaSee] Series error: #{e.message}"
        nil
      end

      def chapters(series_url)
        slug = extract_slug(series_url)
        response = http.get("#{BASE_URL}/manga/#{slug}")
        return [] unless response.status == 200

        # Extract chapters from JavaScript variable
        # vm.Chapters = [{"Chapter":"100100",...}]
        match = response.body.match(/vm\.Chapters\s*=\s*(\[.*?\]);/m)
        return [] unless match

        chapters_data = JSON.parse(match[1])

        chapters_data.map do |ch|
          chapter_num = decode_chapter_number(ch["Chapter"])
          date = ch["Date"] ? Time.parse(ch["Date"]) : nil

          ResultTypes::Chapter.new(
            id: ch["Chapter"],
            title: ch["ChapterName"] || "Chapter #{chapter_num}",
            number: chapter_num.to_s,
            volume: nil,
            language: "en",
            group: "MangaSee",
            published_at: date,
            url: chapter_url(slug, ch["Chapter"])
          )
        end.sort_by { |ch| ch.number.to_f }
      rescue JSON::ParserError, StandardError => e
        Rails.logger.error "[MangaSee] Chapters error: #{e.message}"
        []
      end

      def pages(chapter_url)
        response = http.get(chapter_url)
        return [] unless response.status == 200

        # Extract from JavaScript
        # vm.CurPathName = "..."
        # vm.CurChapter = {...}
        path_match = response.body.match(/vm\.CurPathName\s*=\s*"([^"]+)"/)
        chapter_match = response.body.match(/vm\.CurChapter\s*=\s*(\{.*?\});/m)

        return [] unless path_match && chapter_match

        path_name = path_match[1]
        chapter_data = JSON.parse(chapter_match[1])

        directory = chapter_data["Directory"].presence || ""
        chapter_code = chapter_data["Chapter"]
        page_count = chapter_data["Page"].to_i

        (1..page_count).map do |page_num|
          page_str = page_num.to_s.rjust(3, "0")
          chapter_str = decode_chapter_for_url(chapter_code)

          image_url = if directory.present?
            "https://#{path_name}/manga/#{extract_slug_from_url(chapter_url)}/#{directory}/#{chapter_str}-#{page_str}.png"
          else
            "https://#{path_name}/manga/#{extract_slug_from_url(chapter_url)}/#{chapter_str}-#{page_str}.png"
          end

          ResultTypes::Page.new(
            index: page_num - 1,
            url: image_url,
            mime_type: "image/png"
          )
        end
      rescue JSON::ParserError, StandardError => e
        Rails.logger.error "[MangaSee] Pages error: #{e.message}"
        []
      end

      private

      def extract_slug(id_or_url)
        if id_or_url.include?("/")
          id_or_url.split("/manga/").last&.split("/")&.first || id_or_url
        else
          id_or_url
        end
      end

      def extract_slug_from_url(url)
        url.match(%r{/manga/([^/]+)})[1]
      end

      def extract_info(items, label)
        items.find { |item| item.text.include?(label) }&.css("a")&.map(&:text)&.join(", ")
      end

      # MangaSee chapter number encoding:
      # "100100" = Chapter 1
      # "100150" = Chapter 1.5
      # "101000" = Chapter 10
      def decode_chapter_number(encoded)
        return "0" unless encoded

        # Format: XYYYYY where X is usually 1, YYYY is chapter * 10, Y is decimal
        major = encoded[1..4].to_i
        minor = encoded[5].to_i

        if minor > 0
          "#{major / 10}.#{minor}"
        else
          (major / 10).to_s
        end
      end

      def decode_chapter_for_url(encoded)
        return "0001" unless encoded

        major = encoded[1..4].to_i / 10
        minor = encoded[5].to_i

        if minor > 0
          "#{major.to_s.rjust(4, '0')}.#{minor}"
        else
          major.to_s.rjust(4, "0")
        end
      end

      def chapter_url(slug, chapter_code)
        chapter_str = decode_chapter_for_url(chapter_code)
        "#{BASE_URL}/read-online/#{slug}-chapter-#{chapter_str}.html"
      end
    end
  end

end
