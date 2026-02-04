# frozen_string_literal: true

module UI
  class ToggleSwitchComponent < BaseComponent
    def initialize(form:, method:, label:, description: nil, on_value: "1", off_value: "0", auto_submit: false, disabled: false, **system_arguments)
      super(**system_arguments)
      @form = form
      @method = method
      @label = label
      @description = description
      @on_value = on_value
      @off_value = off_value
      @auto_submit = auto_submit
      @disabled = disabled
    end

    def wrapper_classes
      cn("flex items-start gap-3", system_arguments[:class])
    end

    def track_classes
      "relative inline-flex h-6 w-11 items-center rounded-full border border-zinc-700 bg-zinc-900"
    end

    def knob_classes
      "inline-block h-4 w-4 translate-x-1 rounded-full bg-zinc-200"
    end

    def input_classes
      "peer sr-only"
    end

    def checked_track_classes
      "peer-checked:border-emerald-500/40 peer-checked:bg-emerald-500/15"
    end

    def checked_knob_classes
      "peer-checked:translate-x-6 peer-checked:bg-emerald-300"
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
