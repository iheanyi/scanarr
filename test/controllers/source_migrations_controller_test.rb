require "test_helper"

class SourceMigrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # The fixture ships disabled; migration targets must be usable
    sources(:two).update!(enabled: true)
  end

  test "preview with an unusable target redirects with an error toast" do
    sources(:two).update!(health_status: "broken")

    post preview_source_migrations_path,
         params: { from_source_id: sources(:one).id, to_source_id: sources(:two).id },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_redirected_to source_migrations_path
    assert_includes flash[:alert], "cannot be a migration target"
  end

  test "series_create rejects an unusable target before creating any link" do
    series = series(:one)
    sources(:two).update!(health_status: "broken")

    post library_series_migrate_path(series_slug: series.to_param), params: {
      from_source_id: sources(:one).id,
      to_source_id: sources(:two).id,
      target_series_url: "https://example.com/one-piece"
    }

    assert_redirected_to library_series_path(series_slug: series.to_param)
    assert_includes flash[:alert], "cannot be a migration target"
    # The guard must run before link_series_to_target!
    assert_nil SeriesSource.find_by(series: series, source: sources(:two))
  end

  test "bulk replacement shows persistent results instead of losing unmatched titles in a toast" do
    post source_migrations_path,
         params: { from_source_id: sources(:one).id, to_source_id: sources(:two).id },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "h1", text: "Source replacement results"
    assert_select "a", text: series(:one).canonical_title
  end

  test "series_create links candidate and migrates selected series" do
    series = series(:one)
    from_source = sources(:one)
    to_source = sources(:two)
    follow = user_series_follows(:one)
    follow.update!(source_priority: [ from_source.key ])

    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:series) do |target_url|
      Scrapers::ResultTypes::Series.new(
        id: "TARGET123",
        title: "One Piece",
        url: target_url
      )
    end

    with_stubbed_adapter_registry(registered: true, adapter: fake_adapter) do
      post library_series_migrate_path(series_slug: series.to_param), params: {
        from_source_id: from_source.id,
        to_source_id: to_source.id,
        target_series_url: "https://example.com/one-piece"
      }
    end

    assert_redirected_to library_series_path(series_slug: series.to_param)
    assert_equal "TARGET123", SeriesSource.find_by(series: series, source: to_source)&.source_series_id

    follow.reload

    assert_equal to_source.key, follow.source_priority.first
  end

  test "series_create requires target_series_url for unlinked sources" do
    series = series(:one)
    from_source = sources(:one)
    to_source = sources(:two)

    post library_series_migrate_path(series_slug: series.to_param), params: {
      from_source_id: from_source.id,
      to_source_id: to_source.id
    }

    assert_redirected_to library_series_migration_path(series_slug: series.to_param, from_source_id: from_source.id)
    assert_includes flash[:alert], "choose a source candidate"
    assert_nil SeriesSource.find_by(series: series, source: to_source)
  end

  test "series_create missing target turbo request redirects with flash" do
    series = series(:one)
    from_source = sources(:one)
    to_source = sources(:two)

    post library_series_migrate_path(series_slug: series.to_param),
         params: { from_source_id: from_source.id, to_source_id: to_source.id },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_redirected_to library_series_migration_path(series_slug: series.to_param, from_source_id: from_source.id)
    assert_includes flash[:alert], "Please choose a source candidate first."
  end

  test "series_create rejects link when source identifier is missing" do
    series = series(:one)
    from_source = sources(:one)
    to_source = sources(:two)

    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:series) do |target_url|
      Scrapers::ResultTypes::Series.new(
        id: nil,
        title: "One Piece",
        url: target_url
      )
    end

    with_stubbed_adapter_registry(registered: true, adapter: fake_adapter) do
      post library_series_migrate_path(series_slug: series.to_param), params: {
        from_source_id: from_source.id,
        to_source_id: to_source.id,
        target_series_url: "https://example.com/one-piece"
      }
    end

    assert_redirected_to library_series_migration_path(series_slug: series.to_param, from_source_id: from_source.id)
    assert_includes flash[:alert], "Failed to link/migrate"
    assert_nil SeriesSource.find_by(series: series, source: to_source)
  end

  test "series_create link failure turbo request redirects with flash" do
    series = series(:one)
    from_source = sources(:one)
    to_source = sources(:two)

    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:series) do |target_url|
      Scrapers::ResultTypes::Series.new(
        id: nil,
        title: "One Piece",
        url: target_url
      )
    end

    with_stubbed_adapter_registry(registered: true, adapter: fake_adapter) do
      post library_series_migrate_path(series_slug: series.to_param),
           params: {
             from_source_id: from_source.id,
             to_source_id: to_source.id,
             target_series_url: "https://example.com/one-piece"
           },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    end

    assert_redirected_to library_series_migration_path(series_slug: series.to_param, from_source_id: from_source.id)
    assert_includes flash[:alert], "Failed to link/migrate"
    assert_nil SeriesSource.find_by(series: series, source: to_source)
  end

  test "replacement starts without network discovery and only offers usable providers" do
    sources(:two).update!(health_status: "broken")
    with_stubbed_discovery(->(**) { raise "Unexpected network discovery" }) do
      get library_series_migration_path(series_slug: series(:one).to_param)
    end

    assert_response :success
    assert_select "h1", text: "Replace source"
    assert_select "option[value='#{sources(:two).id}']", 0
    assert_includes response.body, "Your saved chapters, reading history"
  end

  test "replacement shell schedules all eligible providers without waiting for discovery" do
    sources(:two).update!(key: "mangadex")
    with_stubbed_discovery(->(**) { raise "The shell must not call providers" }) do
      get library_series_migration_path(series_slug: series(:one).to_param)
    end

    assert_response :success
    assert_select "option[value='']", text: "All providers"
    assert_select "[data-source-replacement-target='provider'][data-source-id='#{sources(:two).id}']"
    assert_select "[data-source-replacement-target='provider'][data-source-id='#{sources(:mature).id}']"
    assert_select "[data-source-replacement-target='provider'][data-source-id='#{sources(:one).id}']", 0
    assert_includes response.body, "keep your current source"
  end

  test "provider becoming unavailable yields a retryable provider result" do
    sources(:two).update!(health_status: "broken")
    get library_series_migration_path(series_slug: series(:one).to_param, to_source_id: sources(:two).id, matches_only: 1)

    assert_response :success
    assert_select "[data-source-matches='#{sources(:two).id}'][data-source-error='true']"
    assert_includes response.body, "no longer available"
    assert_select "input[value='Use this match']", 0
  end

  test "replacement is scoped to the users followed series before any shared link is written" do
    user_series_follows(:one).destroy!

    assert_no_difference "SeriesSource.count" do
      post library_series_migrate_path(series_slug: series(:one).to_param), params: {
        from_source_id: sources(:one).id, to_source_id: sources(:two).id,
        target_series_url: "https://example.com/title"
      }
    end

    assert_response :not_found
  end

  test "successful replacement checks the new provider immediately" do
    series = series(:one)
    SeriesSource.create!(series: series, source: sources(:two), source_series_id: "TARGET")
    user_series_follows(:one).update!(source_priority: [ sources(:one).key ])

    assert_enqueued_with(job: CheckSourceForChaptersJob, args: [ series.id, user_series_follows(:one).id, sources(:two).id ]) do
      post library_series_migrate_path(series_slug: series.to_param), params: {
        from_source_id: sources(:one).id, to_source_id: sources(:two).id
      }
    end

    assert_redirected_to library_series_path(series_slug: series.to_param)
    assert_includes flash[:notice], "Checking for chapters in the background"
  end

  test "selected provider discovery has a review step without another confirmation dialog" do
    sources(:two).update!(key: "mangadex")
    candidate = SourceMigrationDiscoveryService::Candidate.new(
      source: sources(:two), result: Scrapers::ResultTypes::SearchResult.new(id: "TARGET", title: "One Piece", url: "https://example.com/title"),
      chapter_count: 12, confidence: 1.0, linked: false
    )
    second = candidate.with(result: Scrapers::ResultTypes::SearchResult.new(id: "EDITION2", title: "One Piece — Color Edition", url: "https://example.com/color"))
    discovery = Object.new
    discovery.define_singleton_method(:call) { SourceMigrationDiscoveryService::Result.new(candidates: [ candidate, second ], errors: []) }
    received_source_id = nil
    with_stubbed_discovery(->(**args) { received_source_id = args[:source_id]; discovery }) do
      get library_series_migration_path(series_slug: series(:one).to_param, to_source_id: sources(:two).id, matches_only: 1)
    end

    assert_response :success
    assert_equal sources(:two).id.to_s, received_source_id
    assert_select "input[type=submit][value='Use this match']"
    assert_select "form[action='#{library_series_migrate_path(series_slug: series(:one).to_param)}'] [data-turbo-confirm]", 0
    assert_select "input[name=target_series_url][value='https://example.com/color']"
    assert_select "input[name=target_series_url][value='https://example.com/title']"

    adapter = Object.new
    adapter.define_singleton_method(:series) do |url|
      raise "Wrong match selected" unless url == "https://example.com/color"
      Scrapers::ResultTypes::Series.new(id: "EDITION2", title: "One Piece — Color Edition", url: url)
    end
    with_stubbed_adapter_registry(registered: true, adapter: adapter) do
      post library_series_migrate_path(series_slug: series(:one).to_param), params: {
        from_source_id: sources(:one).id, to_source_id: sources(:two).id,
        target_series_url: "https://example.com/color"
      }
    end

    assert_equal "EDITION2", series(:one).series_sources.find_by!(source: sources(:two)).source_series_id
    assert_redirected_to library_series_path(series_slug: series(:one).to_param)
  end

  private

  def with_stubbed_discovery(factory)
    original = SourceMigrationDiscoveryService.method(:new)
    SourceMigrationDiscoveryService.define_singleton_method(:new, factory)
    yield
  ensure
    SourceMigrationDiscoveryService.define_singleton_method(:new, original)
  end

  def with_stubbed_adapter_registry(registered:, adapter:)
    original_registered = Scrapers::AdapterRegistry.method(:registered?)
    original_for = Scrapers::AdapterRegistry.method(:for)

    Scrapers::AdapterRegistry.define_singleton_method(:registered?) do |_source_key|
      registered
    end
    Scrapers::AdapterRegistry.define_singleton_method(:for) do |_source|
      adapter
    end

    yield
  ensure
    Scrapers::AdapterRegistry.define_singleton_method(:registered?, original_registered)
    Scrapers::AdapterRegistry.define_singleton_method(:for, original_for)
  end
end
