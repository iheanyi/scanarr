# frozen_string_literal: true

module UI
  class AutoSelectComponent < BaseComponent
    def initialize(form:, method:, options:, selected: nil, include_blank: nil, **system_arguments)
      super(**system_arguments)
      @form = form
      @method = method
      @options = options
      @selected = selected
      @include_blank = include_blank
    end

    def select_attributes
      attributes = system_arguments.dup
      attributes[:class] = cn(default_classes, attributes[:class])
      attributes[:data] = select_data.merge(attributes.fetch(:data, {}))
      attributes
    end

    def select_options
      { include_blank: @include_blank }
    end

    private

    def default_classes
      "rounded-md border border-zinc-800 bg-zinc-950 px-2 py-1 text-sm text-zinc-100"
    end

    def select_data
      { controller: "auto-submit", action: "change->auto-submit#submit" }
    end
  end
end
