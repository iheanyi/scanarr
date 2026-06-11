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

  test "create turbo request redirects with flash" do
    post source_migrations_path,
         params: { from_source_id: sources(:one).id, to_source_id: sources(:two).id },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_redirected_to source_migrations_path
    assert_includes flash[:notice], "Migration complete!"
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

  private

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
