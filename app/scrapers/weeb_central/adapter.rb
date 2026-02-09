require "nokogiri"
require "set"

module Scrapers
  module WeebCentral
  class Adapter < Scrapers::BaseAdapter
    SERIES_LINK_SELECTOR = "a[href*='/series/']"
    CHAPTER_LINK_SELECTOR = "a[href*='/chapters/']"
    PAGE_IMAGE_SELECTOR = "img"

    # Maps our standard sort options to WeebCentral's sort values
    SORT_MAP = {
      "latest" => "Latest Updates",
      "popular" => "Popularity",
      "alphabetical" => "Alphabet",
      "subscribers" => "Subscribers",
      "recently_added" => "Recently Added",
      "best_match" => "Best Match"
    }.freeze

    def supports_browse?
      true
    end

    def browse_sort_options
      SORT_MAP.keys
    end

    def browse_page_size
      32
    end

    def browse(sort: "latest", page: 1, limit: 20)
      weeb_sort = SORT_MAP.fetch(sort.to_s, "Latest Updates")
      offset = (page - 1) * limit

      response = http.get(
        "/search/data",
        params: {
          sort: weeb_sort,
          order: "Descending",
          limit: limit,
          offset: offset,
          display_mode: "Full Display"
        },
        headers: { "HX-Request" => "true" }
      )

      doc = Nokogiri::HTML(response.body)
      parse_browse_results(doc)
    end

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
      url = series_url_from_id(id_or_url)
      response = http.get(url)
      doc = Nokogiri::HTML(response.body)
      title = doc.at_css("h1")&.text&.strip
      # Look for the cover image specifically (has "cover" in alt text and 400x600 dimensions)
      cover_img = doc.at_css('img[alt$=" cover"]') || doc.at_css('img[width="400"]')
      cover = cover_img&.[]("src") || cover_img&.[]("data-src")
      author = extract_labeled_text(doc, "Author")
      artist = extract_labeled_text(doc, "Artist")
      status = extract_labeled_text(doc, "Status")
      tags = extract_tags(doc)
      ResultTypes::Series.new(
        id: extract_series_id(url),
        title: title,
        alt_titles: [],
        description: doc.at_css("p")&.text&.strip,
        author: author,
        artist: artist,
        status: normalize_status(status),
        tags: tags,
        series_type: detect_series_type(tags),
        cover_url: cover,
        url: url
      )
    end

    def chapters(series_url)
      url = series_url_from_id(series_url)
      response = http.get(url)
      doc = Nokogiri::HTML(response.body)
      chapter_rows = collect_chapter_rows(doc).to_a
      seen_next_urls = Set.new
      max_pages = config.fetch("max_chapter_pages", nil)

      next_url = next_chapter_page(doc)
      while next_url && !seen_next_urls.include?(next_url) && (max_pages.nil? || seen_next_urls.size < max_pages)
        seen_next_urls << next_url
        fragment = http.get(next_url)
        fragment_doc = Nokogiri::HTML(fragment.body)
        chapter_rows.concat(collect_chapter_rows(fragment_doc).to_a)
        next_url = next_chapter_page(fragment_doc)
      end

      chapter_rows.map.with_index do |row, idx|
        # Handle both structured rows (containing a link) and direct link elements
        link = row.at_css(CHAPTER_LINK_SELECTOR)
        link = row if link.nil? && row.name == "a" && row["href"]&.include?("/chapters/")
        next unless link

        chapter_url = normalize_url(link["href"])
        title = clean_chapter_title(link.text)
        published_at = extract_chapter_date(row)

        ResultTypes::Chapter.new(
          id: extract_chapter_id(chapter_url) || "chapter-#{idx}",
          title: title,
          number: extract_chapter_number(title),
          volume: nil,
          language: nil,
          group: nil,
          published_at: published_at,
          url: chapter_url
        )
      end.compact
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

    def series_url_from_id(id_or_url)
      # Handle full URLs
      return id_or_url if id_or_url.to_s.start_with?("http")
      return normalize_url(id_or_url) if id_or_url.to_s.include?("/")

      # Build URL from just an ID - WeebCentral redirects /series/{id} to the full slug URL
      normalize_url("/series/#{id_or_url}")
    end

    def normalize_url(path_or_url)
      return path_or_url if path_or_url.to_s.start_with?("http")

      base = config.fetch("base_url")
      URI.join(base, path_or_url.to_s).to_s
    end

    def collect_chapter_rows(doc)
      # Strategy 1: Look for #chapter-list with structured div rows (full page)
      chapter_list = doc.at_css("#chapter-list")
      if chapter_list
        rows = chapter_list.css("> div").select { |div| div.at_css(CHAPTER_LINK_SELECTOR) }
        return rows if rows.any?
      end

      # Strategy 2: Find div elements that each contain exactly one chapter link
      # This handles structured HTMX fragments
      all_divs_with_links = doc.css("div").select { |div| div.at_css(CHAPTER_LINK_SELECTOR) }
      single_link_divs = all_divs_with_links.select { |div| div.css(CHAPTER_LINK_SELECTOR).count == 1 }

      # Filter to "leaf" divs - those without child divs also containing chapter links
      leaf_divs = single_link_divs.reject do |div|
        div.css("> div").any? { |child| child.at_css(CHAPTER_LINK_SELECTOR) }
      end

      return leaf_divs if leaf_divs.any?

      # Strategy 3: Return chapter links directly when no structured rows exist
      # The processing code handles both row containers and direct link elements
      doc.css(CHAPTER_LINK_SELECTOR)
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

    def extract_labeled_text(doc, label)
      target = label.to_s.strip.downcase

      dt = doc.css("dt").find { |node| node.text.to_s.strip.downcase == target }
      return dt.next_element&.text&.strip if dt&.next_element

      th = doc.css("th").find { |node| node.text.to_s.strip.downcase == target }
      return th.next_element&.text&.strip if th&.next_element

      label_node = doc.css("span, strong, b").find { |node| node.text.to_s.strip.downcase == target }
      return label_node.next_element&.text&.strip if label_node&.next_element

      nil
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

    def parse_browse_results(doc)
      # Each result is in an article element with bg-base-300 class
      articles = doc.css("article.bg-base-300")

      articles.filter_map do |article|
        parse_browse_article(article)
      end
    end

    def parse_browse_article(article)
      # Find the series link - there are multiple, pick the one with the title
      title_link = article.at_css("section.hidden a[href*='/series/']")
      return nil unless title_link

      url = normalize_url(title_link["href"])
      title = title_link.text.strip

      # Get cover image from the picture element
      cover = extract_cover_from_article(article)

      # Extract metadata from the article's detail section
      detail_section = article.at_css("section.hidden.lg\\:block")
      metadata = extract_browse_metadata(detail_section)

      ResultTypes::BrowseResult.new(
        id: extract_series_id(url),
        title: title,
        url: url,
        cover_url: cover,
        language: nil,
        author: metadata[:author],
        status: metadata[:status],
        last_updated: nil, # Not available in browse results
        chapter_count: nil, # Not available in browse results
        description: nil # Not available in browse results
      )
    end

    def extract_cover_from_article(article)
      # Try to find cover from picture source or img
      picture = article.at_css("picture")
      if picture
        source = picture.at_css("source[srcset]")
        return source["srcset"] if source
      end

      img = article.at_css('img[alt$=" cover"]') || article.at_css("img")
      img&.[]("src") || img&.[]("data-src")
    end

    def extract_browse_metadata(section)
      return {} unless section

      {
        status: extract_text_after_label(section, "Status"),
        author: extract_author_from_section(section)
      }
    end

    def extract_text_after_label(section, label)
      strong = section.css("strong").find { |s| s.text.strip.downcase.start_with?(label.downcase) }
      return nil unless strong

      # The value is in a sibling span
      span = strong.parent&.at_css("span:not(.tooltip)")
      span&.text&.strip
    end

    def extract_author_from_section(section)
      # Authors are in links after "Author(s):"
      author_div = section.css("div").find { |d| d.at_css("strong")&.text&.include?("Author") }
      return nil unless author_div

      author_links = author_div.css("a")
      return nil if author_links.empty?

      author_links.map { |a| a.text.strip }.join(", ")
    end

    def extract_tags(doc)
      # Tags are in links with href containing "included_tag="
      doc.css('a[href*="included_tag="]').map { |a| a.text.strip }.uniq
    end

    def extract_chapter_date(row)
      time_el = row.at_css("time[datetime]")
      return nil unless time_el

      datetime = time_el["datetime"]
      return nil if datetime.blank?

      Time.parse(datetime)
    rescue ArgumentError
      nil
    end

    def detect_series_type(tags)
      tags_lower = tags.map(&:downcase)
      return "manhwa" if tags_lower.any? { |t| t.include?("manhwa") || t.include?("korean") }
      return "manhua" if tags_lower.any? { |t| t.include?("manhua") || t.include?("chinese") }
      return "manga" if tags_lower.any? { |t| t.include?("manga") || t.include?("japanese") }

      "manga" # default
    end
  end
end
end
