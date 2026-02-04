# frozen_string_literal: true

require_relative "base_component"

module UI
  class ButtonComponent < BaseComponent
    def initialize(label: nil, variant: :primary, size: :default, href: nil, type: "button", disabled: false, **system_arguments)
      super(**system_arguments)
      @label = label
      @variant = variant
      @size = size
      @href = href
      @type = type
      @disabled = disabled
    end

    def button_classes
      merge_classes(base_classes, variant_classes, size_classes, system_arguments[:class])
    end

    def button_attributes
      attributes = system_arguments.except(:class).merge(class: button_classes)
      attributes[:disabled] = true if @disabled && !link?
      attributes
    end

    def link?
      @href.present?
    end

    private

    def base_classes
      "inline-flex items-center justify-center rounded-md font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400 focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50"
    end

    def variant_classes
      case @variant.to_sym
      when :primary
        "bg-emerald-500 text-zinc-950 hover:bg-emerald-400"
      when :secondary
        "bg-zinc-800 text-zinc-100 hover:bg-zinc-700"
      when :ghost
        "border border-zinc-700 text-zinc-200 hover:bg-zinc-800/60"
      when :danger
        "bg-rose-500 text-zinc-950 hover:bg-rose-400"
      else
        "bg-emerald-500 text-zinc-950 hover:bg-emerald-400"
      end
    end

    def size_classes
      case @size.to_sym
      when :sm
        "h-8 px-3 text-xs"
      when :lg
        "h-11 px-5 text-sm"
      else
        "h-9 px-4 text-sm"
      end
    end
  end
end
