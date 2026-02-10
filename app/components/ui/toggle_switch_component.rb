# frozen_string_literal: true

module UI
  class ToggleSwitchComponent < BaseComponent
    TRACK_SIZE_CLASSES = {
      sm: "h-5 w-9 p-0.5 ui-toggle-track-sm",
      md: "h-6 w-11 p-0.5 ui-toggle-track-md"
    }.freeze

    KNOB_SIZE_CLASSES = {
      sm: "size-4",
      md: "size-5"
    }.freeze

    KNOB_ICON_SIZE_CLASSES = {
      sm: "h-2.5 w-2.5",
      md: "h-3 w-3"
    }.freeze

    LABEL_SIZE_CLASSES = {
      sm: "text-xs",
      md: "text-sm"
    }.freeze

    LABEL_COLOR_CLASSES = {
      foreground: "text-foreground",
      muted: "text-muted"
    }.freeze

    DESCRIPTION_SIZE_CLASSES = {
      sm: "text-[11px]",
      md: "text-xs"
    }.freeze

    def initialize(form:, method:, label:, description: nil, on_value: "1", off_value: "0", auto_submit: false, disabled: false, size: :md, label_tone: :foreground, **system_arguments)
      super(**system_arguments)
      @form = form
      @method = method
      @label = label
      @description = description
      @on_value = on_value
      @off_value = off_value
      @auto_submit = auto_submit
      @disabled = disabled
      @size = size.to_sym
      @label_tone = label_tone.to_sym
    end

    def wrapper_classes
      cn("flex items-start gap-3", system_arguments[:class])
    end

    def track_classes
      cn(
        "ui-toggle-track relative inline-flex shrink-0 items-center rounded-full",
        TRACK_SIZE_CLASSES[@size] || TRACK_SIZE_CLASSES[:md]
      )
    end

    def track_background_classes
      cn(
        "ui-toggle-track-bg pointer-events-none absolute inset-0 rounded-full"
      )
    end

    def knob_classes
      cn(
        "ui-toggle-knob relative z-10 rounded-full",
        KNOB_SIZE_CLASSES[@size] || KNOB_SIZE_CLASSES[:md]
      )
    end

    def input_classes
      "ui-toggle-input absolute inset-0 size-full appearance-none focus:outline-none"
    end

    def checked_track_classes
      nil
    end

    def label_classes
      cn(
        "block",
        LABEL_COLOR_CLASSES[@label_tone] || LABEL_COLOR_CLASSES[:foreground],
        LABEL_SIZE_CLASSES[@size] || LABEL_SIZE_CLASSES[:md]
      )
    end

    def description_classes
      cn("block text-muted-2 text-pretty", DESCRIPTION_SIZE_CLASSES[@size] || DESCRIPTION_SIZE_CLASSES[:md])
    end

    def knob_icon_classes
      KNOB_ICON_SIZE_CLASSES[@size] || KNOB_ICON_SIZE_CLASSES[:md]
    end

    def input_data
      data = {}
      if @auto_submit
        data[:controller] = "auto-submit"
        data[:action] = "change->auto-submit#submit"
      end
      data
    end

    def input_options
      options = { class: input_classes, data: input_data, disabled: @disabled }
      options.compact
    end
  end
end
