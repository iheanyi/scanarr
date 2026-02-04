# frozen_string_literal: true

module UI
  class DropdownComponent < BaseComponent
    def initialize(label:, items:, align: :right, **system_arguments)
      super(**system_arguments)
      @label = label
      @items = items
      @align = align
    end

    def container_classes
      cn("relative inline-flex", system_arguments[:class])
    end

    def button_classes
      "inline-flex items-center gap-2 rounded-md border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs font-semibold text-zinc-200 hover:border-zinc-500"
    end

    def menu_classes
      cn("absolute z-10 mt-2 w-48 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg", alignment_classes)
    end

    def item_classes(selected:)
      if selected
        "block w-full px-3 py-2 text-left text-xs text-emerald-300 bg-emerald-500/10"
      else
        "block w-full px-3 py-2 text-left text-xs text-zinc-200 hover:bg-zinc-900"
      end
    end

    def alignment_classes
      @align.to_sym == :left ? "left-0" : "right-0"
    end
  end
end
