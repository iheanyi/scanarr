module ResultTypes
  SearchResult = Struct.new(:id, :title, :url, :cover_url, :language, :author, keyword_init: true)

  Series = Struct.new(
    :id,
    :title,
    :alt_titles,
    :description,
    :author,
    :artist,
    :status,
    :tags,
    :series_type,
    :cover_url,
    :url,
    keyword_init: true
  )

  Chapter = Struct.new(
    :id,
    :title,
    :number,
    :volume,
    :language,
    :group,
    :published_at,
    :url,
    keyword_init: true
  )

  Page = Struct.new(:index, :url, :mime_type, keyword_init: true)
end

module Scrapers
  ResultTypes = ::ResultTypes
end
