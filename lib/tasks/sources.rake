namespace :sources do
  desc "Sync Source rows from config/sources/manifest.yml (idempotent)"
  task sync: :environment do
    result = Sources::SyncService.new.call
    puts "[sources:sync] created=#{result.created.size} updated=#{result.updated.size} unchanged=#{result.unchanged.size}"
  end
end

# Upgrades of existing installs run db:prepare, not db:seed, so without this
# hook the manifest would never sync there: no new sources, no version bumps,
# and no health probation window after a deploy.
Rake::Task["db:prepare"].enhance do
  Rake::Task["sources:sync"].invoke
end
