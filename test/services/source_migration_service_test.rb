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
    # Buckets are disjoint; the toast sums them
    refute_includes result.already_on_target, @series

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

  def test_execute_requires_manual_selection_for_distinct_exact_title_matches
    # The second exact title is beyond the old five-result cutoff. Inspect
    # every returned result before deciding that a match is unambiguous.
    results = [ Scrapers::ResultTypes::SearchResult.new(id: "OP", title: "One Piece", url: "https://target.example/original") ]
    4.times do |index|
      results << Scrapers::ResultTypes::SearchResult.new(id: "OTHER#{index}", title: "Another manga", url: "https://target.example/other-#{index}")
    end
    results << Scrapers::ResultTypes::SearchResult.new(id: "OP_COLOR", title: "One Piece", url: "https://target.example/color")
    adapter = FakeAdapter.new(search_results: results,
      series_result: Scrapers::ResultTypes::Series.new(id: "OP", title: "One Piece", url: "https://target.example/original"))
    @follow.update!(source_priority: [ @from_source.key ])

    result = SourceMigrationService.new(from_source: @from_source, to_source: @to_source,
      user: @user, adapter_registry: FakeRegistry.new(adapter)).execute!

    assert result.success
    assert_equal [ @series ], result.no_match
    assert_empty result.migrated
    assert_nil @series.series_sources.find_by(source: @to_source)
    assert_equal [ @from_source.key ], @follow.reload.source_priority
  end

  def test_duplicate_search_rows_for_the_same_target_do_not_prevent_auto_linking
    match = Scrapers::ResultTypes::SearchResult.new(id: "OP", title: "One Piece", url: "https://target.example/original")
    adapter = FakeAdapter.new(search_results: [ match, match.dup ],
      series_result: Scrapers::ResultTypes::Series.new(id: "OP", title: "One Piece", url: match.url))

    result = SourceMigrationService.new(from_source: @from_source, to_source: @to_source,
      user: @user, adapter_registry: FakeRegistry.new(adapter)).execute!

    assert result.success
    assert_equal [ @series ], result.migrated
    assert_equal "OP", @series.series_sources.find_by!(source: @to_source).source_series_id
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
  def test_replacement_moves_an_existing_lower_priority_target_to_the_front
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")
    @follow.update!(source_priority: [ "other_source", @to_source.key, @from_source.key ])

    result = migration_service.execute!

    assert result.success
    assert_equal [ @to_source.key, "other_source" ], @follow.reload.source_priority
    assert_equal @to_source, @follow.preferred_source_for(chapters(:one), @from_source)
  end

  def test_repeated_execution_does_not_rewrite_follow_or_accumulate_results
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")
    service = migration_service
    service.preview
    first = service.execute!
    writes = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      writes << payload[:sql] if payload[:sql].match?(/UPDATE "user_series_follows"/)
    end
    second = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { service.execute! }

    assert_equal [ @series ], first.migrated
    assert_empty first.already_on_target
    assert_empty second.migrated
    assert_equal [ @series ], second.already_on_target
    assert_empty writes
  end

  def test_same_source_is_rejected_without_changing_preferences
    @follow.update!(source_priority: [ "other_source", @from_source.key ])
    service = SourceMigrationService.new(from_source: @from_source, to_source: @from_source, user: @user)

    [ service.preview, service.execute! ].each do |result|
      refute result.success
      assert_match(/different from the current source/, result.errors.first)
    end
    assert_equal [ "other_source", @from_source.key ], @follow.reload.source_priority
  end

  def test_replacement_preserves_other_users_preferences_saved_files_and_reading_progress
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")
    other_follow = UserSeriesFollow.create!(user: users(:member), library_series: @series.library_series,
      source_priority: [ @from_source.key ], download_policy: :auto_download)
    @follow.update!(download_policy: :auto_download, check_interval_minutes: 60)
    progress = ChapterProgress.create!(user: @user, chapter: chapters(:one), page_index: 3,
      page_count: 10, status: "in_progress", progressed_at: Time.current)
    original_progress = progress.attributes
    original_asset = file_assets(:one).attributes
    original_release = releases(:one).attributes
    original_chapter = chapters(:one).attributes

    assert migration_service.execute!.success

    assert_equal [ @from_source.key ], other_follow.reload.source_priority
    assert_equal "auto_download", @follow.reload.download_policy
    assert_equal 60, @follow.check_interval_minutes
    assert_equal original_progress, progress.reload.attributes
    assert_equal original_asset, file_assets(:one).reload.attributes
    assert_equal original_release, releases(:one).reload.attributes
    assert_equal original_chapter, chapters(:one).reload.attributes
    assert @series.series_sources.exists?(source: @from_source)
  end

  def test_selected_series_not_followed_by_the_user_cannot_be_migrated
    SeriesSource.create!(series: @series, source: @to_source, source_series_id: "TARGET123")
    @follow.update!(source_priority: [ @from_source.key ])
    result = SourceMigrationService.new(from_source: @from_source, to_source: @to_source,
      user: users(:member), series_ids: [ @series.id ]).execute!

    assert result.success
    assert_empty result.migrated
    assert_empty result.already_on_target
    assert_equal [ @from_source.key ], @follow.reload.source_priority
  end

  private

  def migration_service
    SourceMigrationService.new(from_source: @from_source, to_source: @to_source, user: @user)
  end
end
