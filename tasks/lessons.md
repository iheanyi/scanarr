# Lessons

- 2026-02-02: Avoid assuming third-party extension bridges (e.g., Mihon). Confirm the source integration approach early and default to first-party scraper framework unless the user explicitly wants an extension ecosystem.
- 2026-02-02: Zeitwerk autoloading expects constants that match file paths; align scraper class/module names with app/scrapers paths to avoid NameError. Also convert Nokogiri NodeSet to arrays before using Array methods like concat.
- 2026-02-02: Don't miss basic Rails conventions. Before running tests, sanity-check Zeitwerk naming (file paths ↔ constants) and avoid obvious autoload pitfalls.
- 2026-02-02: Don't ship download artifacts without anchoring them to core domain models. Define Series/Chapter (and Release/FileAsset as needed) before persisting downloaded content.
- 2026-02-02: Verify git repo state with `git status -sb` before claiming no repo. When using Overseer, use the local DB path
- 2026-02-01: Avoid unnecessary tool calls; never generate images unless explicitly requested.
