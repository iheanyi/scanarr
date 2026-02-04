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
      cn(
        "group relative inline-flex h-6 w-11 shrink-0 items-center rounded-full border border-border bg-surface-2 p-0.5",
        "ring-1 ring-inset ring-border/40 transition-colors duration-200 ease-in-out",
        "focus-within:outline focus-within:outline-2 focus-within:outline-accent focus-within:outline-offset-2",
        "has-[input:checked]:border-accent/60 has-[input:checked]:bg-accent-ghost"
      )
    end

    def knob_classes
      cn(
        "size-5 rounded-full bg-foreground shadow-sm ring-1 ring-border/30",
        "transition-transform duration-200 ease-in-out",
        "group-has-[input:checked]:translate-x-5 group-has-[input:checked]:bg-accent-strong"
      )
    end

    def input_classes
      "absolute inset-0 size-full appearance-none focus:outline-none"
    end

    def checked_track_classes
      nil
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
