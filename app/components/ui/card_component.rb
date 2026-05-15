# frozen_string_literal: true

require_relative "base_component"

module UI
  class CardComponent < BaseComponent
    renders_one :header
    renders_one :footer

    PADDING = {
      none: "",
      sm: "p-4",
      md: "p-5",
      lg: "p-6"
    }.freeze

    RADIUS = {
      none: "rounded-none",
      sm: "rounded-lg",
      md: "rounded-xl",
      lg: "rounded-2xl"
    }.freeze

    def initialize(padding: :md, radius: :lg, interactive: false, elevated: false, **system_arguments)
      super(**system_arguments)
      @padding = padding
      @radius = radius
      @interactive = interactive
      @elevated = elevated
    end

    def card_classes
      cn(
        "border border-border bg-surface",
        RADIUS[@radius.to_sym] || RADIUS[:lg],
        "shadow-none",
        @interactive ? "transition-colors hover:bg-surface-2 hover:border-border-soft cursor-pointer" : nil,
        system_arguments[:class]
      )
    end

    def body_classes
      PADDING[@padding.to_sym] || PADDING[:md]
    end

    def header_classes
      cn(
        "border-b border-border",
        PADDING[@padding.to_sym] || PADDING[:md]
      )
    end

    def footer_classes
      cn(
        "border-t border-border",
        PADDING[@padding.to_sym] || PADDING[:md]
      )
    end
  end
end
