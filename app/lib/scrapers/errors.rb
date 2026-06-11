module Scrapers
  module Errors
    class ScraperError < StandardError; end
    class ChapterNotFoundError < ScraperError; end
    class SeriesNotFoundError < ScraperError; end
    class RateLimitError < ScraperError; end
    class SourceUnavailableError < ScraperError; end
    class InternalHostRefusedError < ScraperError; end
    class BrowseNotSupportedError < ScraperError; end
  end
end
