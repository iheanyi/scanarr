# frozen_string_literal: true

require_relative "base_component"

module UI
  class SearchInputComponent < BaseComponent
    def initialize(placeholder: "Search...", name: :q, value: nil, form: nil, **system_arguments)
      super(**system_arguments)
      @placeholder = placeholder
      @name = name
      @value = value
      @form = form
    end

    def input_classes
      cn(
        "w-full rounded-lg border border-border bg-surface-2 py-2 pl-10 pr-4 text-sm text-foreground",
        "placeholder:text-muted-2 focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent",
        system_arguments[:class]
      )
    end

    def data_attributes
      system_arguments.fetch(:data, {})
    end
  end
end
