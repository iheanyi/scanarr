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
      cn(base_classes, variant_classes, size_classes, system_arguments[:class])
    end

    def button_attributes
      attributes = system_arguments.except(:class).merge(class: button_classes)
      attributes = with_default_turbo_frame_target(attributes) if link?
      attributes[:disabled] = true if @disabled && !link?
      attributes
    end

    def link?
      @href.present?
    end

    private

    def base_classes
      "inline-flex items-center justify-center gap-1.5 rounded-md font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-focus focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:pointer-events-none disabled:opacity-50"
    end

    def variant_classes
      case @variant.to_sym
      when :primary
        "bg-accent text-accent-foreground hover:bg-accent-strong"
      when :secondary
        "bg-surface-2 text-foreground hover:bg-surface"
      when :ghost
        "border border-border text-foreground hover:bg-surface-2 hover:border-border-soft"
      when :danger
        "bg-danger text-foreground hover:bg-danger/90"
      else
        "bg-accent text-accent-foreground hover:bg-accent-strong"
      end
    end

    def size_classes
      case @size.to_sym
      when :sm
        "h-10 sm:h-8 px-3 text-xs"
      when :lg
        "h-11 px-5 text-sm"
      else
        "h-10 sm:h-9 px-4 text-sm"
      end
    end

    def with_default_turbo_frame_target(attributes)
      data_attributes = (attributes[:data] || {}).to_h.deep_symbolize_keys
      data_attributes[:turbo_frame] ||= "_top"
      attributes.merge(data: data_attributes)
    end
  end
end
