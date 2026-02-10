module Scrapers
  module ResultTypes
    SearchResult = Struct.new(
      :id,
      :title,
      :url,
      :cover_url,
      :language,
      :author,
      :chapter_count, # Optional chapter count surfaced during search when available
      keyword_init: true
    )

    # Extended result for browse listings with additional metadata
    BrowseResult = Struct.new(
      :id,
      :title,
      :url,
      :cover_url,
      :language,
      :author,
      :status,           # ongoing, completed, hiatus, cancelled
      :last_updated,     # DateTime of last chapter/update
      :chapter_count,    # Number of chapters (if known)
      :description,      # Short description/synopsis
      keyword_init: true
    )

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
end

ResultTypes = Scrapers::ResultTypes unless defined?(::ResultTypes)
