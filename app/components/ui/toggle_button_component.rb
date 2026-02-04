# frozen_string_literal: true

module UI
  class ToggleButtonComponent < BaseComponent
    def initialize(active:, active_label:, inactive_label:, hover_label:, form_url:, method: :post, **system_arguments)
      super(**system_arguments)
      @active = active
      @active_label = active_label
      @inactive_label = inactive_label
      @hover_label = hover_label
      @form_url = form_url
      @method = method
    end

    def button_label
      @active ? @active_label : @inactive_label
    end

    def button_classes
      cn(base_classes, state_classes, system_arguments[:class])
    end

    def button_data
      data = {
        controller: "toggle-button",
        action: "mouseenter->toggle-button#showHover mouseleave->toggle-button#showDefault",
        toggle_button_active_value: @active,
        toggle_button_active_label_value: @active_label,
        toggle_button_inactive_label_value: @inactive_label,
        toggle_button_hover_label_value: @hover_label
      }

      system_arguments.fetch(:data, {}).merge(data)
    end

    def button_attributes
      system_arguments.except(:class, :data).merge(class: button_classes, data: button_data)
    end

    private

    def base_classes
      "inline-flex items-center gap-2 rounded-md border px-3 py-1.5 text-xs font-semibold transition-colors"
    end

    def state_classes
      if @active
        "border-emerald-500/40 bg-emerald-500/15 text-emerald-300 hover:bg-emerald-500/25"
      else
        "border-zinc-700 bg-zinc-900 text-zinc-300 hover:border-zinc-500 hover:text-zinc-200"
      end
    end
  end
end
