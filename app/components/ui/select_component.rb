# frozen_string_literal: true

module UI
  class SelectComponent < BaseComponent
    SIZES = {
      sm: "h-9 px-3 pr-9 text-xs",
      md: "h-10 px-3.5 pr-10 text-sm",
      lg: "h-11 px-4 pr-11 text-base"
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
      sm: "pl-9",
      md: "pl-10",
      lg: "pl-11"
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
        "appearance-none rounded-lg border border-border/80 bg-surface text-foreground leading-none shadow-sm transition-colors focus:border-accent focus:outline-none focus:ring-2 focus:ring-focus/70 disabled:bg-surface-2 disabled:text-muted",
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
