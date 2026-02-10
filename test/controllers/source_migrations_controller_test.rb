require "test_helper"

class SourceMigrationsControllerTest < ActionDispatch::IntegrationTest
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

    Scrapers::AdapterRegistry.stub(:registered?, true) do
      Scrapers::AdapterRegistry.stub(:for, fake_adapter) do
        post library_series_migrate_path(series_slug: series.to_param), params: {
          from_source_id: from_source.id,
          to_source_id: to_source.id,
          target_series_url: "https://example.com/one-piece"
        }
      end
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

    Scrapers::AdapterRegistry.stub(:registered?, true) do
      Scrapers::AdapterRegistry.stub(:for, fake_adapter) do
        post library_series_migrate_path(series_slug: series.to_param), params: {
          from_source_id: from_source.id,
          to_source_id: to_source.id,
          target_series_url: "https://example.com/one-piece"
        }
      end
    end

    assert_redirected_to library_series_migration_path(series_slug: series.to_param, from_source_id: from_source.id)
    assert_includes flash[:alert], "Failed to link/migrate"
    assert_nil SeriesSource.find_by(series: series, source: to_source)
  end
end
