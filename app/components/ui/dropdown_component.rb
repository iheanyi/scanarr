# frozen_string_literal: true

module UI
  class DropdownComponent < BaseComponent
    def initialize(label:, items:, align: :right, turbo_frame: nil, **system_arguments)
      super(**system_arguments)
      @label = label
      @items = items
      @align = align
      @turbo_frame = turbo_frame
    end

    def container_classes
      cn("relative inline-flex", system_arguments[:class])
    end

    def button_classes
      "inline-flex items-center gap-2 rounded-md border border-border bg-surface-2 px-3 py-1.5 text-xs font-semibold text-foreground hover:border-border-soft"
    end

    def menu_classes
      cn("absolute z-10 mt-2 w-48 rounded-md border border-border bg-surface shadow-lg", alignment_classes)
    end

    def item_classes(selected:)
      if selected
        "block w-full px-3 py-2 text-left text-xs text-accent bg-accent-soft"
      else
        "block w-full px-3 py-2 text-left text-xs text-foreground hover:bg-surface-2"
      end
    end

    def item_data(item)
      data = item.fetch(:data, {})
      data[:turbo_frame] = @turbo_frame if @turbo_frame.present?
      data
    end

    def alignment_classes
      @align.to_sym == :left ? "left-0" : "right-0"
    end
  end
end
