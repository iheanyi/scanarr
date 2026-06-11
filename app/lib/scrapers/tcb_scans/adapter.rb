# frozen_string_literal: true

require "nokogiri"

# TCBScans adapter
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/tcbscans
#
# Domain history (changes frequently due to legal pressure):
#   tcbscans.com, tcbscans.me, tcbscans3.com,
#   tcbscansonepiecechapters.com, tcbscansonepiece.com,
#   tcbonepiecechapters.com (current as of 2025)
#
# Small catalog, pure HTML scraping, no API, no search endpoint.
# Search is implemented by fetching /projects and filtering client-side.
module Scrapers
  module TcbScans
  class Adapter < Scrapers::BaseAdapter
    BASE_URL = "https://tcbonepiecechapters.com"

    def supports_browse?
      false
    end

    def search(query, filters: {})
      _ = filters
      projects = fetch_all_projects
      projects.select { |p| p.title.downcase.include?(query.downcase) }
    rescue StandardError => e
      Rails.logger.error "[TcbScans] Search error: #{e.message}"
      []
    end

    def series(id_or_url)
      url = normalize_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      container = doc.at_css("div.order-1")
      return nil unless container

      title = container.at_css("h1")&.text&.strip
      cover = container.at_css("img")&.[]("src")
      description = container.at_css("p")&.text&.strip

      ResultTypes::Series.new(
        id: extract_path(url),
        title: title,
        alt_titles: [],
        description: description,
        author: nil,
        artist: nil,
        status: "ongoing",
        tags: [],
        series_type: "manga",
        cover_url: absolute_url(cover),
        url: url
      )
    rescue StandardError => e
      Rails.logger.error "[TcbScans] Series error: #{e.message}"
      nil
    end

    def chapters(series_url)
      url = normalize_url(series_url)
      response = http.get(url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      chapter_links = doc.css("div.grid a[href]")

      chapter_links.filter_map do |link|
        href = link["href"]
        next unless href

        full_url = absolute_url(href)

        title_el = link.at_css("div.font-bold:not(.flex)")
        title_text = title_el&.text&.strip
        next unless title_text

        description = link.at_css(".text-gray-500")&.text&.strip

        chapter_num = title_text.match(/(\d+\.?\d*)$/)&.[](1)
        next unless chapter_num

        chapter_title = description.present? ? "Chapter #{chapter_num}: #{description}" : "Chapter #{chapter_num}"

        ResultTypes::Chapter.new(
          id: extract_path(full_url),
          title: chapter_title,
          number: chapter_num,
          volume: nil,
          language: "en",
          group: "TCB Scans",
          published_at: nil,
          url: full_url
        )
      end
    rescue StandardError => e
      Rails.logger.error "[TcbScans] Chapters error: #{e.message}"
      []
    end

    def pages(chapter_url)
      response = http.get(chapter_url)
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      images = doc.css("picture img, .image-container img")

      images.filter_map.with_index do |img, idx|
        src = img["src"]
        next unless src && looks_like_page_url?(src)

        ResultTypes::Page.new(
          index: idx,
          url: absolute_url(src),
          mime_type: guess_mime_type(src)
        )
      end
    rescue StandardError => e
      Rails.logger.error "[TcbScans] Pages error: #{e.message}"
      []
    end

    private

    def fetch_all_projects
      response = http.get("#{base_url}/projects")
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      doc.css("div.bg-card").filter_map do |card|
        link = card.at_css("a[href].text-white")
        next unless link

        href = link["href"]
        title = link.text.strip
        img = card.at_css("img")
        cover = img&.[]("src")

        next unless title.present? && href.present?

        ResultTypes::SearchResult.new(
          id: extract_path(href),
          title: title,
          url: absolute_url(href),
          cover_url: absolute_url(cover),
          author: nil
        )
      end
    end

    def normalize_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      else
        "#{base_url}/#{id_or_url.sub(%r{^/}, '')}"
      end
    end

    def absolute_url(path)
      return nil unless path
      return path if path.start_with?("http")

      "#{base_url}#{path.start_with?('/') ? path : "/#{path}"}"
    end

    def extract_path(url)
      return url unless url
      URI.parse(url).path.sub(%r{^/}, "")
    rescue URI::InvalidURIError
      url
    end

    def looks_like_page_url?(url)
      return false if url.nil?
      return false if url.include?("logo")
      return false if url.include?("avatar")
      return false if url.include?("icon")
      return false if url.include?("favicon")

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
