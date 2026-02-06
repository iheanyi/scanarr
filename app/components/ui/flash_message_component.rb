# frozen_string_literal: true

require_relative "base_component"

module UI
  class FlashMessageComponent < BaseComponent
    VARIANT_CLASSES = {
      success: "border-success-soft bg-success-soft text-success",
      danger: "border-danger/30 bg-danger-soft text-danger",
      warning: "border-warning-soft bg-warning-soft text-warning",
      info: "border-info-soft bg-info-soft text-info"
    }.freeze

    ARIA_ROLES = {
      success: "alert",
      danger: "alert",
      warning: "alert",
      info: "status"
    }.freeze

    ARIA_LIVE = {
      success: "polite",
      danger: "assertive",
      warning: "polite",
      info: "polite"
    }.freeze

    def initialize(variant: :info, message: nil, **system_arguments)
      super(**system_arguments)
      @variant = variant.to_sym
      @message = message
    end

    def render?
      @message.present? || content.present?
    end

    def flash_classes
      cn(
        "rounded-lg border px-4 py-3 text-sm",
        VARIANT_CLASSES[@variant] || VARIANT_CLASSES[:info],
        system_arguments[:class]
      )
    end

    def aria_role
      ARIA_ROLES[@variant]
    end

    def aria_live
      ARIA_LIVE[@variant]
    end

    private

    attr_reader :message
  end
end
