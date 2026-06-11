#!/usr/bin/env ruby
# Codemod for issue #54, rerunnable from the repo root (a second run no-ops):
#   ruby .audit/issue-54-codemod.rb delete_helpers
#     drops the per-adapter base_url helpers now hoisted into
#     Scrapers::BaseAdapter, renaming comick's SITE_URL constant to the
#     fleet-wide BASE_URL name so it can inherit the helper
#   ruby .audit/issue-54-codemod.rb rewrite_constants
#     points bare BASE_URL request builders at the helper, keeping each
#     constant definition as the no-config fallback

HELPER_COPIES = %w[
  batoto comick drake_scans flame_comics isekai_scan like_manga manga_buddy
  manga_clash manga_fire manga_freak manga_geko manga_here manga_kakalot
  manga_nato manga_read manhua_plus manhwa18 tcb_scans toonily zero_scans
].freeze

CONSTANT_CALLERS = %w[asura_scans manga_pill manga_see].freeze

HELPER_PATTERN = /
  \n\n[ ]*def\ base_url
  \n[ ]*(?:@?config\["base_url"\]\ \|\|\ BASE_URL|config\.fetch\("base_url",\ BASE_URL\))
  \n[ ]*end(?=\n)
/x

def adapter_path(key)
  "app/lib/scrapers/#{key}/adapter.rb"
end

def rewrite(path)
  source = File.read(path)
  changed = yield(source)
  if changed == source
    puts "no-op  #{path}"
  else
    File.write(path, changed)
    puts "edited #{path}"
  end
end

case ARGV.first
when "delete_helpers"
  HELPER_COPIES.each do |key|
    rewrite(adapter_path(key)) do |src|
      src = src.gsub(/\bSITE_URL\b/, "BASE_URL") if key == "comick"
      src.sub(HELPER_PATTERN, "")
    end
  end
when "rewrite_constants"
  CONSTANT_CALLERS.each do |key|
    rewrite(adapter_path(key)) do |src|
      src.lines.map do |line|
        line.match?(/^\s*BASE_URL =/) ? line : line.gsub(/\bBASE_URL\b/, "base_url")
      end.join
    end
  end
else
  abort "usage: ruby .audit/issue-54-codemod.rb (delete_helpers|rewrite_constants)"
end
