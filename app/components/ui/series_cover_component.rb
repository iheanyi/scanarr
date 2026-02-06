# frozen_string_literal: true

require_relative "base_component"

module UI
  class SeriesCoverComponent < BaseComponent
    SIZE_CLASSES = {
      xs: "h-12 w-9",
      sm: "h-16 w-12",
      md: "h-24 w-16",
      lg: "h-32 w-24",
      xl: "",
      full: "h-full w-full"
    }.freeze

    ROUNDED_CLASSES = {
      none: "rounded-none",
      sm: "rounded",
      md: "rounded-md",
      lg: "rounded-lg"
    }.freeze

    def initialize(url:, alt: "", size: :md, aspect: nil, rounded: :md, loading: "lazy", **system_arguments)
      super(**system_arguments)
      @url = url
      @alt = alt
      @size = size
      @aspect = aspect
      @rounded = rounded
      @loading = loading
    end

    def container_classes
      cn(
        "overflow-hidden border border-border bg-background",
        SIZE_CLASSES[@size.to_sym] || SIZE_CLASSES[:md],
        @aspect ? "aspect-[#{@aspect}]" : nil,
        ROUNDED_CLASSES[@rounded.to_sym] || ROUNDED_CLASSES[:md],
        system_arguments[:class]
      )
    end

    def has_cover?
      @url.present?
    end

    private

    attr_reader :url, :alt, :loading
  end
end
