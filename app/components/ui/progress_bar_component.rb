# frozen_string_literal: true

require_relative "base_component"

module UI
  class ProgressBarComponent < BaseComponent
    SIZES = {
      xs: "h-1",
      sm: "h-1.5",
      md: "h-2",
      lg: "h-3"
    }.freeze

    COLORS = {
      success: "bg-success",
      info: "bg-info",
      accent: "bg-accent",
      warning: "bg-warning",
      danger: "bg-danger"
    }.freeze

    TRACK_COLORS = {
      default: "bg-border",
      surface: "bg-surface-2"
    }.freeze

    def initialize(value:, max:, color: :info, size: :xs, track: :default, **system_arguments)
      super(**system_arguments)
      @value = value.to_i
      @max = [ max.to_i, 1 ].max
      @color = color
      @size = size
      @track = track
    end

    def percent
      [ (@value.to_f / @max * 100).round, 100 ].min
    end

    def track_classes
      cn("overflow-hidden rounded-full", TRACK_COLORS[@track] || TRACK_COLORS[:default], SIZES[@size] || SIZES[:xs])
    end

    def bar_classes
      cn("h-full rounded-full transition-all", COLORS[@color] || COLORS[:info])
    end
  end
end
