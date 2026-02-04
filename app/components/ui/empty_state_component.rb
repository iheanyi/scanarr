# frozen_string_literal: true

require_relative "base_component"

module UI
  class EmptyStateComponent < BaseComponent
    renders_one :icon
    renders_one :action

    def initialize(title:, description: nil, compact: false, **system_arguments)
      super(**system_arguments)
      @title = title
      @description = description
      @compact = compact
    end

    def container_classes
      cn(
        "flex flex-col items-center justify-center text-center",
        @compact ? "py-8 px-4" : "py-16 px-6",
        system_arguments[:class]
      )
    end

    def icon_wrapper_classes
      cn(
        "flex items-center justify-center rounded-full bg-surface-2 text-muted",
        @compact ? "h-12 w-12 mb-3" : "h-16 w-16 mb-4"
      )
    end

    def title_classes
      cn(
        "font-semibold text-primary",
        @compact ? "text-sm" : "text-lg"
      )
    end

    def description_classes
      cn(
        "text-secondary max-w-sm",
        @compact ? "text-xs mt-1" : "text-sm mt-2"
      )
    end

    def action_wrapper_classes
      @compact ? "mt-4" : "mt-6"
    end

    attr_reader :title, :description
  end
end
