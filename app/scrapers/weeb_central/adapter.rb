require "nokogiri"
require "set"

module WeebCentral
  class Adapter < ::Adapter
    SERIES_LINK_SELECTOR = "a[href*='/series/']"
    CHAPTER_LINK_SELECTOR = "#chapter-list a[href*='/chapters/']"
    PAGE_IMAGE_SELECTOR = "img"

    def search(query)
      response = http.post("/search/simple", params: { location: "main" }, body: { text: query })
      doc = Nokogiri::HTML(response.body)
      nodes = doc.css("a").select { |link| link["href"]&.include?("/series/") }
      results = nodes.map do |link|
        url = normalize_url(link["href"])
        title = link.text.strip
        cover = link.at_css("img")&.[]("src") || link.at_css("img")&.[]("data-src")
        ResultTypes::SearchResult.new(
          id: extract_series_id(url),
          title: title,
          url: url,
          cover_url: cover,
          language: nil
        )
      end
      dedupe_results(results.reject { |r| r.url&.include?("/series/random") })
    end

    def series(id_or_url)
      url = normalize_url(id_or_url)
      response = http.get(url)
      doc = Nokogiri::HTML(response.body)
      title = doc.at_css("h1")&.text&.strip
      cover = doc.at_css("img")&.[]("src") || doc.at_css("img")&.[]("data-src")
      ResultTypes::Series.new(
        id: extract_series_id(url),
        title: title,
        alt_titles: [],
        description: doc.at_css("p")&.text&.strip,
        author: nil,
        artist: nil,
        status: nil,
        tags: [],
        series_type: "manga",
        cover_url: cover,
        url: url
      )
    end

    def chapters(series_url)
      url = normalize_url(series_url)
      response = http.get(url)
      doc = Nokogiri::HTML(response.body)
      chapter_nodes = collect_chapter_nodes(doc).to_a
      seen_next_urls = Set.new
      max_pages = config.fetch("max_chapter_pages", nil)

      next_url = next_chapter_page(doc)
      while next_url && !seen_next_urls.include?(next_url) && (max_pages.nil? || seen_next_urls.size < max_pages)
        seen_next_urls << next_url
        fragment = http.get(next_url)
        fragment_doc = Nokogiri::HTML(fragment.body)
        chapter_nodes.concat(collect_chapter_nodes(fragment_doc).to_a)
        next_url = next_chapter_page(fragment_doc)
      end

      chapter_nodes.map.with_index do |node, idx|
        chapter_url = normalize_url(node["href"])
        title = clean_chapter_title(node.text)
        ResultTypes::Chapter.new(
          id: extract_chapter_id(chapter_url) || "chapter-#{idx}",
          title: title,
          number: extract_chapter_number(title),
          volume: nil,
          language: nil,
          group: nil,
          published_at: nil,
          url: chapter_url
        )
      end
    end

    def pages(chapter_url)
      url = normalize_url(chapter_url)
      response = http.get(url)
      doc = Nokogiri::HTML(response.body)
      images = chapter_images(doc)

      images = images.select { |src| content_image?(src) }
      images.map.with_index do |src, idx|
        ResultTypes::Page.new(index: idx + 1, url: normalize_url(src), mime_type: nil)
      end
    end

    private

    def normalize_url(path_or_url)
      return path_or_url if path_or_url.to_s.start_with?("http")

      base = config.fetch("base_url")
      URI.join(base, path_or_url.to_s).to_s
    end

    def collect_chapter_nodes(doc)
      doc.css(CHAPTER_LINK_SELECTOR)
    end

    def next_chapter_page(doc)
      button = doc.at_css("[hx-get],[data-hx-get]")
      path = button&.[]("hx-get") || button&.[]("data-hx-get")
      path ? normalize_url(path) : nil
    end

    def chapter_images(doc)
      images_url = doc.css("[hx-get]").map { |node| node["hx-get"] }.compact.find { |path| path.include?("/images") }
      if images_url
        response = http.get(images_url, params: { reading_style: "long_strip" })
        images_doc = Nokogiri::HTML(response.body)
        return images_doc.css(PAGE_IMAGE_SELECTOR).map { |img| img["data-src"] || img["src"] }.compact
      end

      doc.css(PAGE_IMAGE_SELECTOR).map { |img| img["data-src"] || img["src"] }.compact
    end

    def extract_series_id(url)
      url.to_s[/\/series\/([^\/]+)/, 1]
    end

    def extract_chapter_id(url)
      url.to_s[/\/chapters\/([^\/]+)/, 1]
    end

    def extract_chapter_number(text)
      text.to_s[/(\d+(\.\d+)?)/, 1]
    end

    def clean_chapter_title(text)
      cleaned = text.to_s.gsub(/\s+/, " ").strip
      cleaned = cleaned.split("Last Read").first.to_s.strip
      cleaned
    end

    def content_image?(src)
      return false if src.nil?

      return false if src.match?(%r{/assets/}i) || src.match?(/logo|icon/i)

      src.include?("/chapters/") || src.include?("/manga/") || src.match?(/\.(jpg|jpeg|png|webp)(\?|$)/i)
    end

    def dedupe_results(results)
      seen = {}
      results.select do |result|
        next false if result.url.nil?

        unless seen[result.url]
          seen[result.url] = true
          true
        end
      end
    end
  end
end

module Scrapers
  module WeebCentral
    Adapter = ::WeebCentral::Adapter
  end
end
