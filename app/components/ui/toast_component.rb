# frozen_string_literal: true

require_relative "base_component"

module UI
  class ToastComponent < BaseComponent
    VARIANTS = {
      success: { icon: "circle-check", color: "text-success", border: "border-l-success" },
      danger: { icon: "circle-alert", color: "text-danger", border: "border-l-danger" },
      error: { icon: "circle-alert", color: "text-danger", border: "border-l-danger" },
      warning: { icon: "triangle-alert", color: "text-warning", border: "border-l-warning" },
      info: { icon: "info", color: "text-info", border: "border-l-info" }
    }.freeze

    def initialize(message:, variant: :success, auto_dismiss: true, **system_arguments)
      super(**system_arguments)
      @message = message
      @variant = variant.to_sym
      @auto_dismiss = auto_dismiss
    end

    def variant_config
      VARIANTS[@variant] || VARIANTS[:info]
    end

    def icon_name
      variant_config[:icon]
    end

    def icon_color
      variant_config[:color]
    end

    def border_class
      variant_config[:border]
    end

    def toast_classes
      cn(
        "translate-y-2 opacity-0 transition-all duration-300 ease-out",
        "flex items-center gap-3 rounded-lg border border-border/80 border-l-2",
        border_class,
        "bg-surface px-4 py-3 shadow-lg backdrop-blur-sm",
        system_arguments[:class]
      )
    end

    def auto_dismiss?
      @auto_dismiss
    end

    private

    attr_reader :message
  end
end
