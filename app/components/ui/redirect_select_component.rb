# frozen_string_literal: true

module UI
  # A standalone select that redirects to the selected URL on change.
  # Used for navigation patterns without forms (e.g., filtering by source).
  #
  # Usage:
  #   <%= render UI::RedirectSelectComponent.new(
  #     options: [
  #       ["All Sources", calendar_path(view: @view_type)],
  #       ["MangaDex", calendar_path(view: @view_type, source: "mangadex")]
  #     ],
  #     selected: current_url,
  #     label: "Filter by source"
  #   ) %>
  class RedirectSelectComponent < BaseComponent
    SIZES = {
      sm: "px-2 py-1.5 pr-7 text-xs",
      md: "px-3 py-2 pr-9 text-sm",
      lg: "px-4 py-2.5 pr-10 text-base"
    }.freeze

    ICON_SIZES = {
      sm: "h-3 w-3 right-2",
      md: "h-4 w-4 right-3",
      lg: "h-5 w-5 right-3"
    }.freeze

    def initialize(options:, selected: nil, label: nil, size: :md, **system_arguments)
      super(**system_arguments)
      @options = options
      @selected = selected
      @label = label
      @size = size
    end

    def select_classes
      cn(
        "appearance-none rounded-md border border-border bg-surface-2 text-foreground cursor-pointer",
        "focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent/30",
        SIZES[@size],
        system_arguments[:class]
      )
    end

    def icon_classes
      ICON_SIZES[@size]
    end

    def select_id
      @select_id ||= system_arguments[:id].presence || "redirect_select_#{object_id}"
    end
  end
end
