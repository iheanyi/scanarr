# frozen_string_literal: true

require_relative "base_component"

module UI
  class InputComponent < BaseComponent
    SIZES = {
      sm: "h-8 px-2.5 text-xs",
      md: "h-9 px-3 text-sm",
      lg: "h-11 px-4 text-base"
    }.freeze

    def initialize(
      form: nil,
      method: nil,
      name: nil,
      type: "text",
      value: nil,
      placeholder: nil,
      label: nil,
      hint: nil,
      error: nil,
      size: :md,
      disabled: false,
      required: false,
      **system_arguments
    )
      super(**system_arguments)
      @form = form
      @method = method
      @name = name
      @type = type
      @value = value
      @placeholder = placeholder
      @label = label
      @hint = hint
      @error = error
      @size = size
      @disabled = disabled
      @required = required
    end

    def input_classes
      cn(
        "w-full rounded-md border bg-surface text-primary placeholder:text-tertiary",
        "focus:outline-none focus:ring-2 focus:ring-focus focus:border-accent",
        "disabled:cursor-not-allowed disabled:opacity-50",
        @error ? "border-error" : "border-border",
        SIZES[@size.to_sym] || SIZES[:md],
        system_arguments[:class]
      )
    end

    def input_attributes
      attrs = {
        type: @type,
        placeholder: @placeholder,
        disabled: @disabled,
        required: @required,
        class: input_classes
      }
      attrs[:value] = @value if @value.present? && !@form
      attrs[:name] = @name if @name.present? && !@form
      attrs.merge(system_arguments.except(:class))
    end

    def use_form_helper?
      @form.present? && @method.present?
    end

    attr_reader :form, :method, :label, :hint, :error, :required
  end
end
