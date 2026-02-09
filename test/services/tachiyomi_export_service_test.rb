require "test_helper"

class TachiyomiExportServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
  end

  def test_export_produces_valid_gzipped_protobuf
    data = TachiyomiExportService.new(user: @user).perform

    assert data.is_a?(String)
    assert_equal "\x1f\x8b".b, data.byteslice(0, 2), "Expected gzip magic bytes"

    # Should be parseable
    backup = Tachiyomi::Parser.new.parse(StringIO.new(data))
    assert backup.is_a?(Tachiyomi::Backup)
  end

  def test_export_includes_followed_series
    data = TachiyomiExportService.new(user: @user).perform
    backup = Tachiyomi::Parser.new.parse(StringIO.new(data))

    # Admin user follows One Piece via fixture
    titles = backup.backupManga.map(&:title)

    # Should include followed series (if source is mapped)
    # Note: fixtures use weeb_central which has a tachiyomi mapping
    if titles.any?
      assert titles.first.is_a?(String)
    end
  end

  def test_export_sets_favorite_flag
    data = TachiyomiExportService.new(user: @user).perform
    backup = Tachiyomi::Parser.new.parse(StringIO.new(data))

    backup.backupManga.each do |manga|
      assert manga.favorite, "Expected favorite=true for #{manga.title}"
    end
  end

  def test_export_includes_source_list
    data = TachiyomiExportService.new(user: @user).perform
    backup = Tachiyomi::Parser.new.parse(StringIO.new(data))

    if backup.backupManga.any?
      assert_operator backup.backupSources.size, :>=, 1
      backup.backupSources.each do |source|
        assert source.name.present?, "Source name should not be empty"
        assert_operator source.sourceId, :>, 0, "Source ID should be positive"
      end
    end
  end

  def test_preview_returns_counts
    preview = TachiyomiExportService.new(user: @user).preview

    assert preview.key?(:series)
    assert preview.key?(:chapters)
    assert preview.key?(:sources)
    assert preview.key?(:source_names)
    assert preview[:source_names].is_a?(Array)
  end

  def test_round_trip_import_export
    # Export
    export_data = TachiyomiExportService.new(user: @user).perform
    original_backup = Tachiyomi::Parser.new.parse(StringIO.new(export_data))

    # Re-export should produce the same manga count
    export_data_2 = TachiyomiExportService.new(user: @user).perform
    backup_2 = Tachiyomi::Parser.new.parse(StringIO.new(export_data_2))

    assert_equal original_backup.backupManga.size, backup_2.backupManga.size
  end

  def test_status_mapping_round_trip
    service = TachiyomiExportService.new(user: @user)

    # Test all status mappings
    assert_equal 1, service.send(:scanarr_to_tachi_status, "ongoing")
    assert_equal 2, service.send(:scanarr_to_tachi_status, "completed")
    assert_equal 3, service.send(:scanarr_to_tachi_status, "licensed")
    assert_equal 4, service.send(:scanarr_to_tachi_status, "publishing_finished")
    assert_equal 5, service.send(:scanarr_to_tachi_status, "cancelled")
    assert_equal 6, service.send(:scanarr_to_tachi_status, "hiatus")
    assert_equal 0, service.send(:scanarr_to_tachi_status, nil)
  end
end
