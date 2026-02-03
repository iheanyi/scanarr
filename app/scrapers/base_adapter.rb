class BaseAdapter
  # Custom error classes for scraper operations
  class ScraperError < StandardError; end
  class ChapterNotFoundError < ScraperError; end
  class SeriesNotFoundError < ScraperError; end
  class RateLimitError < ScraperError; end
  class SourceUnavailableError < ScraperError; end

  attr_reader :config, :http

  def initialize(config:, http: HttpClient.new(config: config))
    @config = config
    @http = http
  end

  def search(_query)
    raise NotImplementedError, "#{self.class}#search not implemented"
  end

  def series(_id_or_url)
    raise NotImplementedError, "#{self.class}#series not implemented"
  end

  def chapters(_series_url)
    raise NotImplementedError, "#{self.class}#chapters not implemented"
  end

  def pages(_chapter_url)
    raise NotImplementedError, "#{self.class}#pages not implemented"
  end
end

module Scrapers
  BaseAdapter = ::BaseAdapter
end
