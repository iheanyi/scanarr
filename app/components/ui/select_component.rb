# frozen_string_literal: true

module UI
  class SelectComponent < BaseComponent
    SIZES = {
      sm: "px-2 py-1.5 pr-7 text-xs",
      md: "px-3 py-2 pr-9 text-sm",
      lg: "px-4 py-2.5 pr-10 text-base"
    }.freeze

    ICON_SIZES = {
      sm: "h-3 w-3 right-2",
      md: "h-4 w-4 right-3",
      lg: "h-5 w-5 right-3"
    }.freeze

    def initialize(form:, method:, options:, selected: nil, include_blank: nil, label: nil, hint: nil, size: :md, full_width: true, **system_arguments)
      super(**system_arguments)
      @form = form
      @method = method
      @options = options
      @selected = selected
      @include_blank = include_blank
      @label = label
      @hint = hint
      @size = size
      @full_width = full_width
    end

    def select_attributes
      classes = cn(
        "appearance-none rounded-md border border-border bg-surface-2 text-foreground focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent/30",
        SIZES[@size],
        @full_width ? "block w-full" : "inline-block",
        system_arguments[:class]
      )
      data = system_arguments.fetch(:data, {})

      system_arguments.except(:class, :data).merge(class: classes, data: data)
    end

    def select_options
      { include_blank: @include_blank }
    end

    def icon_classes
      ICON_SIZES[@size]
    end
  end
end
