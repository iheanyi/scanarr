# Reports adapters whose BASE_URL fallback constant disagrees with their
# manifest base_url. A divergent constant means registry-less construction
# (tests, console probes) targets a different host than the fleet manifest;
# reconcile deliberately rather than letting the two drift.
#
# Run with: bin/rails runner script/audit_adapter_base_urls.rb

divergent = Scrapers::Manifest.entries.filter_map do |entry|
  klass = entry.adapter_class
  next unless klass.const_defined?(:BASE_URL)

  constant = klass::BASE_URL
  next if constant == entry.base_url

  [ entry.key, constant, entry.base_url ]
end

if divergent.empty?
  puts "all adapter BASE_URL constants match the manifest"
else
  divergent.each do |key, constant, manifest|
    puts "#{key}: constant #{constant} != manifest #{manifest}"
  end
  exit 1
end
