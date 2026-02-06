# frozen_string_literal: true

require_relative "base_component"

module UI
  class StatCardComponent < BaseComponent
    COLOR_CLASSES = {
      warning: "text-warning",
      info: "text-info",
      accent: "text-accent",
      danger: "text-danger",
      success: "text-success",
      muted: "text-muted"
    }.freeze

    def initialize(label:, value:, color: :muted, **system_arguments)
      super(**system_arguments)
      @label = label
      @value = value
      @color = color.to_sym
    end

    def value_classes
      cn("text-2xl font-semibold", COLOR_CLASSES[@color] || COLOR_CLASSES[:muted])
    end

    private

    attr_reader :label, :value
  end
end
