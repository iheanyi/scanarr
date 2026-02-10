require "test_helper"

class SourceMigrationServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @from_source = sources(:one) # weeb_central
    @to_source = sources(:two)   # example_source
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

  def test_preview_identifies_unmatchable_series
    # Series is on from_source but not on to_source
    result = SourceMigrationService.new(
      from_source: @from_source,
      to_source: @to_source,
      user: @user
    ).preview

    assert result.success
    assert_includes result.no_match, @series
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
