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
        "w-full rounded-md border bg-surface-2 text-foreground placeholder:text-muted-2",
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
        id: input_id,
        class: input_classes
      }
      attrs[:value] = @value if @value.present?
      attrs[:name] = @name if @name.present? && !@form
      attrs[:aria] = aria_attributes if aria_attributes.present?
      attrs.merge(system_arguments.except(:class))
    end

    def use_form_helper?
      @form.present? && @method.present?
    end

    def input_id
      @input_id ||= begin
        provided_id = system_arguments[:id]
        if provided_id.present?
          provided_id
        elsif use_form_helper?
          "#{@form.object_name}_#{@method}"
        elsif @name.present?
          @name.to_s.parameterize(separator: "_")
        else
          "input_#{object_id}"
        end
      end
    end

    def hint_id
      "#{input_id}_hint"
    end

    def error_id
      "#{input_id}_error"
    end

    def aria_attributes
      attrs = {}
      described_by_ids = []
      described_by_ids << hint_id if @hint.present? && @error.blank?
      described_by_ids << error_id if @error.present?
      attrs[:describedby] = described_by_ids.join(" ") if described_by_ids.any?
      attrs[:invalid] = true if @error.present?
      attrs
    end

    attr_reader :form, :method, :label, :hint, :error, :required
  end
end
