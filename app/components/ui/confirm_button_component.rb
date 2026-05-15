# frozen_string_literal: true

require_relative "base_component"

module UI
  class ConfirmButtonComponent < BaseComponent
    VARIANT_CLASSES = {
      danger: "inline-flex h-9 shrink-0 items-center gap-1.5 rounded-lg border border-danger/40 bg-danger-soft/60 px-3 text-xs font-semibold leading-none text-danger shadow-sm transition-all hover:bg-danger-soft",
      warning: "inline-flex h-9 shrink-0 items-center gap-1.5 rounded-lg border border-warning/40 bg-warning-soft/60 px-3 text-xs font-semibold leading-none text-warning shadow-sm transition-all hover:bg-warning-soft",
      accent: "inline-flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-lg border border-accent/40 bg-accent-soft/60 px-3 text-xs font-semibold leading-none text-accent shadow-sm transition-all hover:bg-accent-soft",
      info: "inline-flex h-9 shrink-0 items-center gap-1.5 rounded-lg border border-info/40 bg-info-soft/60 px-3 text-xs font-medium leading-none text-info shadow-sm transition-all hover:bg-info-soft"
    }.freeze

    COUNT_CLASSES = {
      danger: "rounded-full bg-danger/20 px-1.5 py-0.5 text-xs",
      warning: "rounded-full bg-warning/20 px-1.5 py-0.5 text-xs",
      accent: "rounded-full bg-accent/20 px-1.5 py-0.5 text-xs",
      info: "rounded-full bg-info/20 px-1.5 py-0.5 text-xs"
    }.freeze

    COMPACT_VARIANT_CLASSES = {
      danger: "inline-flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-danger hover:bg-danger-soft",
      warning: "inline-flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-warning hover:bg-warning-soft",
      accent: "inline-flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-accent hover:bg-accent-soft",
      info: "inline-flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-info hover:bg-info-soft"
    }.freeze

    def initialize(label:, url:, confirm:, icon:, variant: :danger, method: :post, count: nil, compact: false, params: nil, title: nil, **system_arguments)
      super(**system_arguments)
      @label = label
      @url = url
      @confirm = confirm
      @icon_name = icon
      @variant = variant.to_sym
      @method = method
      @count = count
      @compact = compact
      @params = params
      @title = title
    end

    def button_classes
      if @compact
        cn(COMPACT_VARIANT_CLASSES[@variant] || COMPACT_VARIANT_CLASSES[:danger], system_arguments[:class])
      else
        cn(VARIANT_CLASSES[@variant] || VARIANT_CLASSES[:danger], system_arguments[:class])
      end
    end

    def count_classes
      COUNT_CLASSES[@variant] || COUNT_CLASSES[:danger]
    end

    def icon_size
      @compact ? "h-3.5 w-3.5" : "h-4 w-4"
    end
  end
end
