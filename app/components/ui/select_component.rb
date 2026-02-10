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

    LEADING_ICON_SIZES = {
      sm: "ml-2.5 h-4 w-4",
      md: "ml-3 h-4 w-4",
      lg: "ml-3 h-5 w-5"
    }.freeze

    LEADING_ICON_PADDING = {
      sm: "pl-8",
      md: "pl-9",
      lg: "pl-10"
    }.freeze

    def initialize(form:, method:, options:, selected: nil, include_blank: nil, label: nil, hint: nil, size: :md, full_width: true, leading_icon: nil, **system_arguments)
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
      @leading_icon = leading_icon
    end

    def select_attributes
      classes = cn(
        "appearance-none rounded-md border border-border bg-surface-2 text-foreground focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent/30",
        SIZES[@size],
        has_leading_icon? ? LEADING_ICON_PADDING[@size] : nil,
        has_leading_icon? ? "col-start-1 row-start-1" : nil,
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

    def chevron_icon_classes
      if has_leading_icon?
        base = ICON_SIZES[@size].to_s.sub(/right-\d+/, "")
        cn(base, "col-start-1 row-start-1 mr-2 self-center justify-self-end")
      else
        icon_classes
      end
    end

    def has_leading_icon?
      @leading_icon.present?
    end

    def leading_icon_name
      @leading_icon
    end

    def leading_icon_classes
      LEADING_ICON_SIZES[@size]
    end
  end
end
