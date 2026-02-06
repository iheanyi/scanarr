# frozen_string_literal: true

require_relative "base_component"

module UI
  class StatusBadgeComponent < BaseComponent
    STATUS_VARIANTS = {
      # Download statuses
      "downloading" => :accent,
      "complete" => :info,
      "failed" => :danger,
      "queued" => :warning,
      "pending" => :warning,
      "cancelled" => :default,
      # Series statuses
      "ongoing" => :info,
      "completed" => :success,
      "hiatus" => :warning,
      # Reading progress
      "in progress" => :warning,
      # Scraper run statuses
      "success" => :success,
      "error" => :danger,
      "running" => :info
    }.freeze

    VARIANT_CLASSES = {
      success: "bg-success-soft text-success",
      warning: "bg-warning-soft text-warning",
      danger: "bg-danger-soft text-danger",
      info: "bg-info-soft text-info",
      accent: "bg-accent-soft text-accent",
      default: "bg-surface-2 text-muted"
    }.freeze

    def initialize(status:, label: nil, bordered: false, **system_arguments)
      super(**system_arguments)
      @status = status.to_s.downcase
      @label = label || @status.titleize
      @bordered = bordered
    end

    def badge_classes
      variant = STATUS_VARIANTS[@status] || :default
      cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
        VARIANT_CLASSES[variant],
        @bordered ? border_class(variant) : nil,
        system_arguments[:class]
      )
    end

    private

    def border_class(variant)
      case variant
      when :accent then "border border-accent/30"
      when :danger then "border border-danger/30"
      when :info then "border border-info/30"
      when :warning then "border border-warning/30"
      when :success then "border border-success/30"
      else "border border-border"
      end
    end
  end
end
