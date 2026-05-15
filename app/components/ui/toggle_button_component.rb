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
      "inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3 text-xs font-semibold leading-none transition-all"
    end

    def state_classes
      if @active
        "border-accent/30 bg-accent-soft text-accent-strong shadow-sm hover:border-accent/40 hover:bg-accent-soft"
      else
        "border-border/80 bg-background/60 text-muted shadow-sm hover:border-border-soft hover:text-foreground"
      end
    end
  end
end
