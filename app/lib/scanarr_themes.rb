module ScanarrThemes
  DEFAULT = "signal-coral"

  THEMES = [
    {
      id: "signal-coral",
      name: "Signal Coral",
      mood: "Noir control room",
      accent: "#ef6a72",
      surface: "#141820",
      base: "#0a0c10",
      summary: "Charcoal UI with a coral action language. Still expressive, but warmer and less arcade than cyan.",
      best_for: "Download queues, destructive actions, hot/new status, and pages that need sharper command hierarchy.",
      tags: [ "Default", "Command", "Warm", "Direct" ],
      meta_color: "#0a0c10"
    },
    {
      id: "archive-noir",
      name: "Archive Noir",
      mood: "Museum-dark utility",
      accent: "#66d9c2",
      surface: "#12161d",
      base: "#090b0f",
      summary: "A restrained graphite system with mint used only for intent. The app recedes and the manga covers carry the color.",
      best_for: "A mature default that works across browse, library, reader, and admin surfaces without feeling themed.",
      tags: [ "Neutral", "Quiet" ],
      meta_color: "#090b0f"
    },
    {
      id: "panel-pulse",
      name: "Panel Pulse",
      mood: "Electric manga-tech",
      accent: "#5ee7ff",
      surface: "#101b2c",
      base: "#08111c",
      summary: "The previous live baseline. High energy, blue-cyan, status-forward, and the most dashboard-like option.",
      best_for: "Browse screens and operational state, but it is also the one most likely to feel over-styled.",
      tags: [ "Legacy", "Cyan", "Kinetic" ],
      meta_color: "#08111c"
    },
    {
      id: "oxide-shelf",
      name: "Oxide Shelf",
      mood: "Industrial archive",
      accent: "#7bc8a4",
      surface: "#151915",
      base: "#0b0d0b",
      summary: "Carbon, oxidized green, and copper. More physical and library-like without going beige or bookstore-cute.",
      best_for: "Collections, source browsing, and a product personality that feels durable rather than flashy.",
      tags: [ "Earthy", "Shelf", "Tactile" ],
      meta_color: "#0b0d0b"
    },
    {
      id: "acid-zine",
      name: "Acid Zine",
      mood: "Underground manga zine",
      accent: "#d7ff5f",
      surface: "#15151a",
      base: "#070708",
      summary: "A deliberately stranger option: black, paper-white, acid chartreuse, and magenta status notes.",
      best_for: "Testing how far the brand can move before it becomes too loud. Useful even if we do not ship it.",
      tags: [ "Experimental", "Graphic", "Loud" ],
      meta_color: "#070708"
    },
    {
      id: "ink-noir",
      name: "Ink Noir",
      mood: "Cinematic reader",
      accent: "#f04367",
      surface: "#0d1219",
      base: "#05070b",
      summary: "A high-contrast reader aesthetic that treats chapter pages and covers like the star of the product.",
      best_for: "Immersive chapter reading, punchy covers, and cleaner hierarchy under pressure.",
      tags: [ "Archive", "Cinematic" ],
      meta_color: "#05070b"
    },
    {
      id: "editorial-shelf",
      name: "Editorial Shelf",
      mood: "Premium bookstore",
      accent: "#d8a665",
      surface: "#1b1e24",
      base: "#111318",
      summary: "A warmer curated-library direction with richer metadata framing and a collectible shelf tone.",
      best_for: "Library browsing, discovery, and series pages that should feel more curated.",
      tags: [ "Archive", "Editorial" ],
      meta_color: "#111318"
    }
  ].freeze

  OPTIONS = THEMES.map do |theme|
    label = theme.fetch(:id) == DEFAULT ? "#{theme.fetch(:name)} (default)" : theme.fetch(:name)
    [ label, theme.fetch(:id) ]
  end.freeze

  module_function

  def ids
    THEMES.map { |theme| theme.fetch(:id) }
  end

  def normalize(value, fallback: DEFAULT)
    theme = value.to_s.strip
    theme = fallback if theme.empty?

    ids.include?(theme) ? theme : fallback
  end

  def find(value)
    id = normalize(value)
    THEMES.find { |theme| theme.fetch(:id) == id }
  end

  def meta_color(value)
    find(value).fetch(:meta_color)
  end
end
