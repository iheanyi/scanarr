# frozen_string_literal: true

require_relative "base_component"

module UI
  class SeriesCoverComponent < BaseComponent
    renders_one :fallback
    renders_one :overlay

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

    # Full class names so Tailwind JIT can detect them at build time.
    ASPECT_CLASSES = {
      "2/3" => "aspect-[2/3]",
      "3/4" => "aspect-[3/4]",
      "1/1" => "aspect-square",
      "16/9" => "aspect-video"
    }.freeze

    def initialize(url:, alt: "", size: :md, aspect: nil, rounded: :md, loading: "lazy", image_class: nil, framed: true, fallback_url: nil, **system_arguments)
      super(**system_arguments)
      @url = url.presence || fallback_url
      @alt = alt
      @size = size
      @aspect = aspect
      @rounded = rounded
      @loading = loading
      @image_class = image_class
      @framed = framed
      @fallback_url = fallback_url if url.present? && fallback_url.present? && fallback_url != url
    end

    def container_classes
      cn(
        "relative block overflow-hidden",
        @framed ? "border border-border bg-background" : nil,
        SIZE_CLASSES[@size.to_sym] || SIZE_CLASSES[:md],
        @aspect ? ASPECT_CLASSES[@aspect.to_s] : nil,
        ROUNDED_CLASSES[@rounded.to_sym] || ROUNDED_CLASSES[:md],
        system_arguments[:class]
      )
    end

    def image_classes
      cn("block h-full w-full object-cover", @image_class)
    end

    def has_cover?
      @url.present?
    end

    def image_data_attributes
      return {} if @fallback_url.blank?

      { fallback_url: @fallback_url }
    end

    def image_error_handler
      "var fallback=this.dataset.fallbackUrl;if(fallback){this.removeAttribute('data-fallback-url');this.src=fallback;return;}#{show_fallback_script}"
    end

    def image_load_handler
      "if(this.naturalWidth===0){#{image_error_handler}}"
    end

    private

    attr_reader :url, :alt, :loading

    def show_fallback_script
      "var f=this.parentElement.querySelector('[data-cover-fallback]');this.style.display='none';if(f)f.style.display='flex';"
    end
  end
end
