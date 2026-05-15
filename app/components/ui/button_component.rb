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
      "inline-flex shrink-0 items-center justify-center gap-2 whitespace-nowrap rounded-lg font-semibold leading-none transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-focus focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:pointer-events-none disabled:opacity-50"
    end

    def variant_classes
      case @variant.to_sym
      when :primary
        "border border-accent/25 bg-accent text-accent-foreground shadow-[0_12px_30px_rgba(102,224,255,0.12)] hover:border-accent/40 hover:bg-accent-strong"
      when :secondary
        "border border-border/80 bg-surface text-foreground shadow-sm hover:border-border-soft hover:bg-surface-2"
      when :ghost
        "border border-border/80 bg-background/60 text-foreground shadow-sm hover:border-accent/20 hover:bg-surface"
      when :danger
        "border border-danger/30 bg-danger text-foreground shadow-[0_12px_24px_rgba(255,127,154,0.08)] hover:bg-danger/90"
      else
        "border border-accent/25 bg-accent text-accent-foreground shadow-[0_12px_30px_rgba(102,224,255,0.12)] hover:border-accent/40 hover:bg-accent-strong"
      end
    end

    def size_classes
      case @size.to_sym
      when :sm
        "h-9 px-3 text-xs"
      when :lg
        "h-11 px-5 text-sm"
      else
        "h-10 px-4 text-sm"
      end
    end

    def with_default_turbo_frame_target(attributes)
      data_attributes = (attributes[:data] || {}).to_h.deep_symbolize_keys
      data_attributes[:turbo_frame] ||= "_top"
      attributes.merge(data: data_attributes)
    end
  end
end
