require "test_helper"

class SourceMigrationServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @from_source = sources(:one) # weeb_central
    @to_source = sources(:two)   # example_source
    # The fixture ships disabled; migration targets must be usable
    @to_source.update!(enabled: true)
    @series = series(:one)       # One Piece, linked to library_series :one
    @follow = user_series_follows(:one)
  end

  def test_preview_categorizes_series_already_on_target
    # series :one already has series_source :one (weeb_central)
    # Add a second source for migration target
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    ).preview

    assert result.success
    assert_includes result.already_on_target, @series
    assert_empty result.no_match
  end

  def test_preview_classifies_unlinked_series_as_link_candidates
    # Series is on from_source but not on to_source; execute! would attempt
    # an auto-link, so preview must present it as a candidate, not a no_match
    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    ).preview

    assert result.success
    assert_includes result.link_candidates, @series
    assert_empty result.no_match
    assert_empty result.already_on_target
  end

  def test_preview_and_execute_reject_a_broken_target_source
    @to_source.update!(health_status: "broken")
    service = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    )

    [ service.preview, service.execute! ].each do |result|
      refute result.success
      assert_match(/is broken and cannot be a migration target/, result.errors.first)
      assert_empty result.migrated
    end
  end

  def test_preview_and_execute_reject_a_disabled_target_source
    @to_source.update!(enabled: false, health_status: "healthy")
    service = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    )

    [ service.preview, service.execute! ].each do |result|
      refute result.success
      assert_match(/is disabled and cannot be a migration target/, result.errors.first)
    end
  end

  def test_migrating_from_a_broken_source_still_works
    @from_source.update!(health_status: "broken")
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    ).execute!

    assert result.success
    assert_includes result.migrated, @series
  end

  def test_preview_without_auto_link_identifies_unmatchable_series
    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      auto_link: false
    ).preview

    assert result.success
    assert_includes result.no_match, @series
    assert_empty result.link_candidates
    assert_empty result.already_on_target
  end

  def test_execute_updates_source_priority
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    ).execute!

    assert result.success
    assert_includes result.migrated, @series

    @follow.reload

    assert_equal [ @to_source.key ], @follow.source_priority
  end

  def test_execute_skips_series_without_target
    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    ).execute!

    assert result.success
    assert_empty result.migrated
    assert_includes result.no_match, @series
  end

  def test_execute_removes_old_source_from_priority
    # Set initial priority with old source
    @follow.update!(source_priority: [ @from_source.key, "other_source" ])
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")

    SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    ).execute!

    @follow.reload

    assert_equal @to_source.key, @follow.source_priority.first
    refute_includes @follow.source_priority, @from_source.key
  end

  def test_preview_filters_to_selected_series_ids
    second_library_series = LibrarySeries.create!(canonical_title: "Bleach", status: "ongoing")
    second_series = Series.create!(canonical_title: "Bleach", library_series: second_library_series)
    UserSeriesFollow.create!(user: @user, library_series: second_library_series, download_policy: :notify_only)
    SeriesSource.create!(series: second_series, source: @from_source, source_series_id: "BLEACH_FROM")
    SeriesSource.create!(series: second_series, source: @to_source, source_series_id: "BLEACH_TO")

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      series_ids: [ second_series.id ]
    ).preview

    assert_includes result.already_on_target, second_series
    refute_includes result.already_on_target, @series
    assert_empty result.no_match
  end

  def test_execute_only_migrates_selected_series_ids
    second_library_series = LibrarySeries.create!(canonical_title: "Naruto", status: "ongoing")
    second_series = Series.create!(canonical_title: "Naruto", library_series: second_library_series)
    second_follow = UserSeriesFollow.create!(user: @user, library_series: second_library_series, download_policy: :notify_only)
    SeriesSource.create!(series: second_series, source: @from_source, source_series_id: "NARUTO_FROM")
    SeriesSource.create!(series: second_series, source: @to_source, source_series_id: "NARUTO_TO")
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "ONEPIECE_TO")
    @follow.update!(source_priority: [ @from_source.key ])
    second_follow.update!(source_priority: [ @from_source.key ])

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      series_ids: [ second_series.id ]
    ).execute!

    assert_includes result.migrated, second_series
    refute_includes result.migrated, @series

    @follow.reload
    second_follow.reload

    assert_equal [ @from_source.key ], @follow.source_priority
    assert_equal [ @to_source.key ], second_follow.source_priority
  end

  class FakeAdapter
    def initialize(search_results:, series_result:)
      @search_results = search_results
      @series_result = series_result
    end

    def search(_query, filters: {})
      @search_results
    end

    def series(_id_or_url)
      @series_result
    end
  end

  class FakeRegistry
    def initialize(adapter)
      @adapter = adapter
    end

    def registered?(_key)
      true
    end

    def for(_source)
      @adapter
    end
  end

  def test_execute_auto_links_a_high_confidence_match_on_the_target
    adapter = FakeAdapter.new(
      search_results: [ Scrapers::ResultTypes::SearchResult.new(id: "OP", title: "One Piece", url: "https://target.example/one-piece") ],
      series_result: Scrapers::ResultTypes::Series.new(id: "OP", title: "One Piece", url: "https://target.example/one-piece")
    )

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      adapter_registry: FakeRegistry.new(adapter)
    ).execute!

    assert result.success
    assert_includes result.migrated, @series
    assert_empty result.no_match

    link = @series.series_sources.find_by(source: @to_source)

    assert_equal "OP", link.source_series_id

    @follow.reload

    assert_equal [ @to_source.key ], @follow.source_priority
  end

  def test_execute_does_not_auto_link_containment_matches
    adapter = FakeAdapter.new(
      search_results: [ Scrapers::ResultTypes::SearchResult.new(id: "OPA", title: "One Piece Academy", url: "https://target.example/one-piece-academy") ],
      series_result: Scrapers::ResultTypes::Series.new(id: "OPA", title: "One Piece Academy", url: "https://target.example/one-piece-academy")
    )

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      adapter_registry: FakeRegistry.new(adapter)
    ).execute!

    assert result.success
    assert_includes result.no_match, @series
    assert_nil @series.series_sources.find_by(source: @to_source)
  end

  def test_execute_leaves_low_confidence_matches_unlinked
    adapter = FakeAdapter.new(
      search_results: [ Scrapers::ResultTypes::SearchResult.new(id: "X", title: "Completely Different Title", url: "https://target.example/x") ],
      series_result: nil
    )

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      adapter_registry: FakeRegistry.new(adapter)
    ).execute!

    assert result.success
    assert_includes result.no_match, @series
    assert_nil @series.series_sources.find_by(source: @to_source)
  end

  def test_execute_records_error_and_continues_when_target_search_fails
    adapter = Object.new
    def adapter.search(_query, filters: {})
      raise Scrapers::Errors::SourceUnavailableError, "site is down"
    end

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      adapter_registry: FakeRegistry.new(adapter)
    ).execute!

    refute result.success
    assert_includes result.no_match, @series
    assert result.errors.any? { |message| message.include?("site is down") }
  end

  def test_execute_with_auto_link_disabled_keeps_unlinked_series_as_no_match
    adapter = FakeAdapter.new(
      search_results: [ Scrapers::ResultTypes::SearchResult.new(id: "OP", title: "One Piece", url: "https://target.example/one-piece") ],
      series_result: Scrapers::ResultTypes::Series.new(id: "OP", title: "One Piece", url: "https://target.example/one-piece")
    )

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      auto_link: false,
      adapter_registry: FakeRegistry.new(adapter)
    ).execute!

    assert_includes result.no_match, @series
    assert_nil @series.series_sources.find_by(source: @to_source)
  end

  def test_execute_with_empty_selection_migrates_nothing
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")
    @follow.update!(source_priority: [ @from_source.key ])

    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user,
      series_ids: []
    ).execute!

    assert result.success
    assert_empty result.migrated
    assert_empty result.already_on_target
    assert_empty result.no_match

    @follow.reload

    assert_equal [ @from_source.key ], @follow.source_priority
  end
end
