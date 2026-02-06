# frozen_string_literal: true

module UI
  class PaginationComponent < BaseComponent
    # @param collection [Object] Kaminari-paginated collection
    # @param base_path [String] Base URL path (e.g., reading_history_path)
    # @param params [Hash] Additional query params to preserve
    # @param window [Integer] Number of pages to show on each side of current
    def initialize(collection:, base_path:, params: {}, window: 3)
      @collection = collection
      @base_path = base_path
      @params = params.to_h.symbolize_keys.except(:page)
      @window = window
      super()
    end

    def render?
      @collection.respond_to?(:total_pages) && @collection.total_pages > 1
    end

    private

    def page_url(page_num)
      query = @params.compact.merge(page: page_num).to_query
      query.present? ? "#{@base_path}?#{query}" : @base_path
    end

    def start_page
      [ @collection.current_page - @window, 1 ].max
    end

    def end_page
      [ @collection.current_page + @window, @collection.total_pages ].min
    end
  end
end
