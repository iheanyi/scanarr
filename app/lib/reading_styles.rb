module ReadingStyles
  CANONICAL = %w[left_to_right right_to_left vertical webtoon].freeze

  LEGACY_ALIASES = {
    "webcomic" => "vertical",
    "vertical_paged" => "vertical",
    "long_strip" => "webtoon",
    "continuous_vertical" => "webtoon"
  }.freeze

  OPTIONS = [
    [ "Left to Right", "left_to_right" ],
    [ "Right to Left", "right_to_left" ],
    [ "Vertical (Paged)", "vertical" ],
    [ "Webtoon (Continuous)", "webtoon" ]
  ].freeze

  module_function

  def normalize(value, fallback: "left_to_right")
    style = value.to_s.strip
    style = fallback if style.empty?
    style = LEGACY_ALIASES.fetch(style, style)

    return style if CANONICAL.include?(style)

    fallback
  end
end
