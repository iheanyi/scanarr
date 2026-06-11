#!/usr/bin/env ruby
# Codemod for issue #54: adapters must honor config["base_url"] over their
# BASE_URL constant. BaseAdapter now owns the fallback helper, so this script
# (1) deletes the per-adapter duplicate helpers, (2) renames comick's SITE_URL
# constant to the fleet-wide BASE_URL name, and (3) rewrites the three adapters
# that still interpolate the constant in request builders. Rerunnable; a second
# run is a no-op.
#
# Usage: ruby .audit/issue-54-base-url-codemod.rb [--check]
#   --check  report what would change without writing

DUPLICATE_HELPER = /\n\n[ ]*def base_url\n[ ]*(?:@?config\["base_url"\] \|\| (?:BASE_URL|SITE_URL)|config\.fetch\("base_url", (?:BASE_URL|SITE_URL)\))\n[ ]*end\n/

CONSTANT_INTERPOLATORS = %w[asura_scans manga_see manga_pill].freeze

check_only = ARGV.include?("--check")
changed = []

Dir.glob("app/lib/scrapers/*/adapter.rb").sort.each do |path|
  key = File.basename(File.dirname(path))
  source = File.read(path)
  rewritten = source.gsub(DUPLICATE_HELPER, "\n")

  rewritten = rewritten.gsub("SITE_URL", "BASE_URL") if key == "comick"

  if CONSTANT_INTERPOLATORS.include?(key)
    rewritten = rewritten.gsub('#{BASE_URL}', '#{base_url}')
    rewritten = rewritten.gsub("http.get(BASE_URL)", "http.get(base_url)")
  end

  next if rewritten == source

  changed << key
  File.write(path, rewritten) unless check_only
end

puts "#{check_only ? 'would change' : 'changed'}: #{changed.join(', ')}"

offenders = Dir.glob("app/lib/scrapers/*/adapter.rb").flat_map do |path|
  File.readlines(path).each_with_index.filter_map do |line, index|
    next if line.match?(/\A\s*BASE_URL\s*=/)
    "#{path}:#{index + 1}" if line.include?("BASE_URL")
  end
end

if offenders.empty?
  puts "clean: BASE_URL appears only in constant definitions"
else
  puts "offenders:"
  puts offenders
  exit 1
end
