class RemapManganatoChapterUrlsToWww < ActiveRecord::Migration[8.1]
  # The MangaNato manifest base_url moved from the apex natomanga.com to the
  # canonical www host. A manifest domain change does not migrate stored
  # URLs the way the recovery-adoption path does, so existing chapters and
  # releases keep absolute apex URLs that reader/download paths feed to
  # adapter.pages. HttpClient does not follow redirects, so those 301s would
  # fail until refetched. Rewrite the prefix in place.
  OLD_PREFIX = "https://natomanga.com".freeze
  NEW_PREFIX = "https://www.natomanga.com".freeze

  def up
    source_id = exec_query("SELECT id FROM sources WHERE key = 'manga_nato' LIMIT 1").rows.dig(0, 0)
    return unless source_id

    [ "chapters", "releases" ].each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET source_url = #{quote(NEW_PREFIX)} || SUBSTRING(source_url FROM #{OLD_PREFIX.length + 1})
        WHERE source_id = #{quote(source_id)}
          AND source_url LIKE #{quote("#{OLD_PREFIX}/%")}
      SQL
    end
  end

  def down
    source_id = exec_query("SELECT id FROM sources WHERE key = 'manga_nato' LIMIT 1").rows.dig(0, 0)
    return unless source_id

    [ "chapters", "releases" ].each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET source_url = #{quote(OLD_PREFIX)} || SUBSTRING(source_url FROM #{NEW_PREFIX.length + 1})
        WHERE source_id = #{quote(source_id)}
          AND source_url LIKE #{quote("#{NEW_PREFIX}/%")}
      SQL
    end
  end

  private

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
