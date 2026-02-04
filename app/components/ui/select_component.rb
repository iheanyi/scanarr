# frozen_string_literal: true

module UI
  class SelectComponent < BaseComponent
    def initialize(form:, method:, options:, selected: nil, include_blank: nil, label: nil, hint: nil, **system_arguments)
      super(**system_arguments)
      @form = form
      @method = method
      @options = options
      @selected = selected
      @include_blank = include_blank
      @label = label
      @hint = hint
    end

    def select_attributes
      classes = cn(
        "block w-full appearance-none rounded-md border border-border bg-surface-2 px-3 py-2 pr-9 text-sm text-foreground focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent/30",
        system_arguments[:class]
      )
      data = system_arguments.fetch(:data, {})

      system_arguments.except(:class, :data).merge(class: classes, data: data)
    end

    def select_options
      { include_blank: @include_blank }
    end
  end
end
