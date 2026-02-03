require "json"

module Mangadex
  class Adapter < ::Adapter
    def search(query)
      response = http.get("/manga", params: { title: query, limit: 20, includes: [ "cover_art" ] })
      payload = JSON.parse(response.body)
      payload.fetch("data", []).map do |item|
        attrs = item.fetch("attributes", {})
        title = pick_title(attrs.fetch("title", {}))
        cover = cover_url(item)
        ResultTypes::SearchResult.new(
          id: item.fetch("id"),
          title: title,
          url: "https://mangadex.org/title/#{item.fetch('id')}",
          cover_url: cover,
          language: attrs["originalLanguage"]
        )
      end
    end

    def series(id_or_url)
      id = extract_manga_id(id_or_url)
      response = http.get("/manga/#{id}", params: { includes: [ "cover_art", "author", "artist" ] })
      item = JSON.parse(response.body).fetch("data")
      attrs = item.fetch("attributes", {})
      authors = relationship_names(item, "author")
      artists = relationship_names(item, "artist")
      ResultTypes::Series.new(
        id: item.fetch("id"),
        title: pick_title(attrs.fetch("title", {})),
        alt_titles: attrs.fetch("altTitles", []).map { |t| t.values.first }.compact,
        description: pick_title(attrs.fetch("description", {})),
        author: authors.first,
        artist: artists.first,
        status: attrs["status"],
        tags: attrs.fetch("tags", []).map { |tag| pick_title(tag.fetch("attributes", {}).fetch("name", {})) }.compact,
        series_type: type_from_language(attrs["originalLanguage"]),
        cover_url: cover_url(item),
        url: "https://mangadex.org/title/#{item.fetch('id')}"
      )
    end

    def chapters(series_url)
      id = extract_manga_id(series_url)
      chapters = []
      offset = 0
      limit = 100

      loop do
        response = http.get(
          "/chapter",
          params: {
            manga: id,
            limit: limit,
            offset: offset,
            translatedLanguage: [ "en" ],
            order: { chapter: "asc" }
          }
        )
        payload = JSON.parse(response.body)
        payload.fetch("data", []).each do |item|
          attrs = item.fetch("attributes", {})
          chapters << ResultTypes::Chapter.new(
            id: item.fetch("id"),
            title: attrs["title"],
            number: attrs["chapter"],
            volume: attrs["volume"],
            language: attrs["translatedLanguage"],
            group: attrs["scanlationGroup"],
            published_at: attrs["publishAt"],
            url: "https://mangadex.org/chapter/#{item.fetch('id')}"
          )
        end
        total = payload.fetch("total", chapters.size)
        offset += limit
        break if offset >= total
      end

      chapters
    end

    def pages(chapter_url)
      id = extract_chapter_id(chapter_url)
      response = http.get("/at-home/server/#{id}")
      payload = JSON.parse(response.body)
      base = payload.fetch("baseUrl")
      hash = payload.fetch("chapter").fetch("hash")
      files = payload.fetch("chapter").fetch("data")

      files.map.with_index do |filename, idx|
        ResultTypes::Page.new(index: idx + 1, url: "#{base}/data/#{hash}/#{filename}", mime_type: nil)
      end
    end

    private

    def pick_title(title_hash)
      return nil if title_hash.nil?

      title_hash["en"] || title_hash.values.compact.first
    end

    def extract_manga_id(id_or_url)
      url = id_or_url.to_s
      return url if url.match?(/\A[0-9a-f-]{36}\z/i)

      url[/\/title\/([0-9a-f-]{36})/i, 1] || url
    end

    def extract_chapter_id(id_or_url)
      url = id_or_url.to_s
      return url if url.match?(/\A[0-9a-f-]{36}\z/i)

      url[/\/chapter\/([0-9a-f-]{36})/i, 1] || url
    end

    def cover_url(item)
      cover = item.fetch("relationships", []).find { |rel| rel["type"] == "cover_art" }
      filename = cover&.dig("attributes", "fileName")
      return nil if filename.nil?

      "https://uploads.mangadex.org/covers/#{item.fetch('id')}/#{filename}"
    end

    def relationship_names(item, type)
      item.fetch("relationships", [])
          .select { |rel| rel["type"] == type }
          .map { |rel| rel.dig("attributes", "name") }
          .compact
    end

    def type_from_language(lang)
      case lang.to_s
      when "ja"
        "manga"
      when "ko"
        "manhwa"
      when "zh"
        "manhua"
      else
        "manga"
      end
    end
  end
end

module Scrapers
  module Mangadex
    Adapter = ::Mangadex::Adapter
  end
end
