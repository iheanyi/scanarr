RailsIcons.configure do |config|
  config.default_library = "lucide"
  config.default_variant = "outline"

  # Lucide defaults - clean, consistent sizing
  config.libraries.lucide.default_variant = "outline"
  config.libraries.lucide.outline.default.css = "size-5"
  config.libraries.lucide.outline.default.stroke_width = "1.5"
end
