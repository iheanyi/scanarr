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
      merge_classes(base_classes, variant_classes, system_arguments[:class])
    end

    private

    def base_classes
      "inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold"
    end

    def variant_classes
      case @variant.to_sym
      when :success
        "bg-emerald-500/15 text-emerald-300"
      when :warning
        "bg-amber-500/15 text-amber-300"
      when :danger
        "bg-rose-500/15 text-rose-300"
      else
        "bg-zinc-800 text-zinc-200"
      end
    end
  end
end
