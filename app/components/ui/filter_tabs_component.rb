# frozen_string_literal: true

require_relative "base_component"

module UI
  class FilterTabsComponent < BaseComponent
    ACTIVE_VARIANTS = {
      default: "bg-surface-2 text-foreground",
      success: "bg-success-soft text-success",
      warning: "bg-warning-soft text-warning",
      accent: "bg-accent-soft text-accent",
      info: "bg-info-soft text-info",
      primary: "bg-accent text-accent-foreground"
    }.freeze

    INACTIVE_CLASSES = "text-muted hover:text-foreground hover:bg-surface-2"

    # items: Array of hashes with keys:
    #   label: (String) display text
    #   href: (String) link path
    #   active: (Boolean) is this tab currently selected?
    #   variant: (Symbol) active color variant (default: :default)
    #   icon: (String, optional) Lucide icon name to prepend
    def initialize(items:, size: :md, **system_arguments)
      super(**system_arguments)
      @items = items
      @size = size
    end

    def container_classes
      cn(
        "flex overflow-hidden rounded-lg border border-border",
        @size == :sm ? "text-xs" : "text-sm",
        @size == :sm ? "bg-surface-2/60" : "bg-surface-2/60",
        system_arguments[:class]
      )
    end

    def item_classes(item, index)
      active = item[:active]
      variant = (item[:variant] || :default).to_sym
      cn(
        @size == :sm ? "px-2.5 py-1" : "px-3 py-1.5",
        "transition-colors",
        index > 0 ? "border-l border-border" : nil,
        active ? (ACTIVE_VARIANTS[variant] || ACTIVE_VARIANTS[:default]) : INACTIVE_CLASSES
      )
    end
  end
end
