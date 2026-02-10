# frozen_string_literal: true

module UI
  class PaginationComponent < BaseComponent
    # @param collection [Object] Kaminari-paginated collection
    # @param base_path [String] Base URL path (e.g., reading_history_path)
    # @param params [Hash] Additional query params to preserve
    # @param window [Integer] Number of pages to show on each side of current
    # @param turbo_frame [String, nil] Turbo Frame ID to target for pagination links
    def initialize(collection:, base_path:, params: {}, window: 2, turbo_frame: nil)
      @collection = collection
      @base_path = base_path
      @params = params.to_h.symbolize_keys.except(:page)
      @window = window
      @turbo_frame = turbo_frame
      super()
    end

    def render?
      @collection.respond_to?(:total_pages) && @collection.total_pages > 1
    end

    def total_pages
      @collection.total_pages
    end

    def current_page
      @collection.current_page
    end

    # Returns an array of page numbers and :gap symbols for rendering
    # e.g., [1, :gap, 5, 6, 7, 8, 9, :gap, 34]
    def page_numbers
      pages = []
      total = total_pages
      current = current_page

      # Always include first page
      pages << 1

      # Calculate window around current page
      window_start = [ current - @window, 2 ].max
      window_end = [ current + @window, total - 1 ].min

      # Add gap or sequential pages after first page
      if window_start > 2
        pages << :gap
      elsif window_start == 2
        pages << 2
      end

      # Add window pages
      (window_start..window_end).each do |p|
        pages << p unless pages.include?(p)
      end

      # Add gap or sequential pages before last page
      if window_end < total - 1
        pages << :gap
      elsif window_end == total - 1
        pages << total - 1 unless pages.include?(total - 1)
      end

      # Always include last page
      pages << total unless pages.include?(total)

      pages
    end

    private

    def link_data
      data = { turbo_action: "advance" }
      data[:turbo_frame] = @turbo_frame if @turbo_frame
      data
    end

    def page_url(page_num)
      query = @params.compact.merge(page: page_num).to_query
      query.present? ? "#{@base_path}?#{query}" : @base_path
    end
  end
end
