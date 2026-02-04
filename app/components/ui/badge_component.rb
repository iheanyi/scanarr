# frozen_string_literal: true

require_relative "base_component"

module UI
  class BadgeComponent < BaseComponent
    def initialize(label:, variant: :default, **system_arguments)
      super(**system_arguments)
      @label = label
      @variant = variant
    end

    def badge_classes
      cn(base_classes, variant_classes, system_arguments[:class])
    end

    private

    def base_classes
      "inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold"
    end

    def variant_classes
      case @variant.to_sym
      when :success
        "bg-success-soft text-success"
      when :warning
        "bg-warning-soft text-warning"
      when :danger, :error
        "bg-error-soft text-error"
      when :info
        "bg-info-soft text-info"
      when :accent
        "bg-accent-soft text-accent"
      else
        "bg-surface-2 text-secondary"
      end
    end
  end
end
