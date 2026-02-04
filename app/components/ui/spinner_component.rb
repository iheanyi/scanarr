# frozen_string_literal: true

require_relative "base_component"

module UI
  class SpinnerComponent < BaseComponent
    SIZES = {
      xs: "h-3 w-3",
      sm: "h-4 w-4",
      md: "h-6 w-6",
      lg: "h-8 w-8",
      xl: "h-12 w-12"
    }.freeze

    def initialize(size: :md, label: "Loading...", **system_arguments)
      super(**system_arguments)
      @size = size
      @label = label
    end

    def spinner_classes
      cn(
        "animate-spin text-accent",
        SIZES[@size.to_sym] || SIZES[:md],
        system_arguments[:class]
      )
    end

    attr_reader :label
  end
end
