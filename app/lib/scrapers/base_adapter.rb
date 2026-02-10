module Scrapers
  class BaseAdapter
    # Browse sort options
    SORT_OPTIONS = %w[latest popular alphabetical].freeze

    attr_reader :config, :http

    def initialize(config:, http: HttpClient.new(config: config))
      @config = config
      @http = http
    end

    def search(_query, filters: {})
      _ = filters
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

    # Browse the source catalog. Optional - not all sources support this.
    # @param sort [String] One of: latest, popular, alphabetical
    # @param page [Integer] Page number (1-indexed)
    # @param limit [Integer] Results per page
    # @return [Array<ResultTypes::BrowseResult>]
    def browse(sort: "latest", page: 1, limit: 20, filters: {})
      _ = sort
      _ = page
      _ = limit
      _ = filters
      raise Scrapers::Errors::BrowseNotSupportedError, "#{self.class} does not support browsing"
    end

    # Whether this adapter supports search functionality
    def supports_search?
      true
    end

    # Whether this adapter supports browse functionality
    def supports_browse?
      false
    end

    # Whether this adapter accepts server-side filter params for search/browse.
    def supports_server_side_filters?
      false
    end

    # Supported browse filters in [label, value] pairs.
    # Example: { genres: [["Action", "action"]], statuses: [["Ongoing", "ongoing"]] }
    def browse_filter_options
      {}
    end

    # Supported search filters in [label, value] pairs.
    # Example: { genres: [["Action", "action"]], statuses: [["Ongoing", "ongoing"]] }
    def search_filter_options
      {}
    end

    # Available sort options for browse (can be overridden by adapters)
    def browse_sort_options
      SORT_OPTIONS
    end

    # Results per page for browse. Override in adapters with known API limits.
    def browse_page_size
      20
    end

    # Normalize status strings from various sources to standard values.
    # Returns: "ongoing", "completed", "hiatus", "cancelled"
    # Defaults to "ongoing" for unrecognized values.
    def normalize_status(status)
      case status&.downcase
      when /ongoing/, /releasing/, /publishing/
        "ongoing"
      when /complete/, /finished/
        "completed"
      when /hiatus/
        "hiatus"
      when /cancel/, /dropped/
        "cancelled"
      else
        "ongoing"
      end
    end
  end
end
