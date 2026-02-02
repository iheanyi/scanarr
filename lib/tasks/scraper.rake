namespace :scraper do
  desc "Search WeebCentral: rake scraper:search[query]"
  task :search, [ :query ] => :environment do |_t, args|
    config = Rails.configuration.scraper_sources.fetch("weeb_central", {})
    adapter = WeebCentral::Adapter.new(config: config)
    results = adapter.search(args[:query].to_s)
    results.each { |r| puts "#{r.title} -> #{r.url}" }
  end

  desc "Fetch series details: rake scraper:series[url]"
  task :series, [ :url ] => :environment do |_t, args|
    config = Rails.configuration.scraper_sources.fetch("weeb_central", {})
    adapter = WeebCentral::Adapter.new(config: config)
    series = adapter.series(args[:url].to_s)
    puts series.inspect
  end

  desc "Fetch chapters: rake scraper:chapters[url]"
  task :chapters, [ :url ] => :environment do |_t, args|
    config = Rails.configuration.scraper_sources.fetch("weeb_central", {})
    adapter = WeebCentral::Adapter.new(config: config)
    chapters = adapter.chapters(args[:url].to_s)
    chapters.each { |c| puts "#{c.number} #{c.title} -> #{c.url}" }
  end

  desc "Fetch pages: rake scraper:pages[url]"
  task :pages, [ :url ] => :environment do |_t, args|
    config = Rails.configuration.scraper_sources.fetch("weeb_central", {})
    adapter = WeebCentral::Adapter.new(config: config)
    pages = adapter.pages(args[:url].to_s)
    pages.each { |p| puts "#{p.index} #{p.url}" }
  end
end
