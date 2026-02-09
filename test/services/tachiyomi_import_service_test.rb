require "test_helper"

class TachiyomiImportServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @source = sources(:one) # weeb_central
  end

  def test_import_manga_with_matching_source
    backup_data = build_backup(
      source_id: 2131019126180322627, # weeb_central
      title: "New Import Manga",
      url: "/manga/new-import",
      chapters: [
        { url: "/ch/1", name: "Chapter 1", number: 1.0, read: true },
        { url: "/ch/2", name: "Chapter 2", number: 2.0, read: false }
      ]
    )

    result = TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(backup_data),
      strategy: :merge
    ).perform

    assert result.success, "Expected success but got errors: #{result.errors.inspect}"
    assert_operator result.imported[:series], :>=, 1
    assert_equal 2, result.imported[:chapters]
  end

  def test_import_skips_unmapped_sources
    backup_data = build_backup(
      source_id: 999999999, # Unknown source
      title: "Unknown Source Manga",
      url: "/manga/unknown"
    )

    result = TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(backup_data),
      strategy: :merge
    ).perform

    assert result.success
    assert_equal 0, result.imported[:series]
    assert_equal 1, result.skipped[:series]
    assert_equal 1, result.unmapped_sources.size
  end

  def test_import_dedupes_by_title
    # Create existing series with same title
    existing = Series.find_by(canonical_title: "One Piece") || series(:one)

    backup_data = build_backup(
      source_id: 2131019126180322627,
      title: existing.canonical_title,
      url: "/manga/one-piece-tachi"
    )

    series_count_before = Series.count

    TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(backup_data),
      strategy: :merge
    ).perform

    # Should not create a duplicate series
    assert_equal series_count_before, Series.count
  end

  def test_import_creates_follow
    backup_data = build_backup(
      source_id: 2131019126180322627,
      title: "Follow Test Manga",
      url: "/manga/follow-test"
    )

    result = TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(backup_data),
      strategy: :merge
    ).perform

    assert result.success
    assert_operator result.imported[:follows], :>=, 1
  end

  def test_import_with_tracking
    backup = Tachiyomi::Backup.new(
      backupManga: [
        Tachiyomi::BackupManga.new(
          source: 2131019126180322627,
          url: "/manga/tracked",
          title: "Tracked Manga",
          favorite: true,
          tracking: [
            Tachiyomi::BackupTracking.new(syncId: 2, mediaId: 12345, title: "Tracked Manga"),
            Tachiyomi::BackupTracking.new(syncId: 1, mediaId: 67890, title: "Tracked Manga")
          ]
        )
      ],
      backupSources: [
        Tachiyomi::BackupSource.new(name: "Weeb Central", sourceId: 2131019126180322627)
      ]
    )

    encoded = Tachiyomi::Backup.encode(backup)
    gzipped = Zlib.gzip(encoded)

    result = TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(gzipped),
      strategy: :merge
    ).perform

    assert result.success
    assert_operator result.imported[:tracking], :>=, 1
  end

  def test_import_read_status
    backup_data = build_backup(
      source_id: 2131019126180322627,
      title: "Read Status Manga",
      url: "/manga/read-status",
      chapters: [
        { url: "/ch/1", name: "Chapter 1", number: 1.0, read: true },
        { url: "/ch/2", name: "Chapter 2", number: 2.0, read: false }
      ]
    )

    result = TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(backup_data),
      strategy: :merge
    ).perform

    assert result.success
    assert_equal 1, result.imported[:progress] # Only the read chapter
  end

  def test_preview_returns_stats
    backup_data = build_backup(
      source_id: 2131019126180322627,
      title: "Preview Manga",
      url: "/manga/preview",
      chapters: [
        { url: "/ch/1", name: "Ch 1", number: 1.0, read: true }
      ]
    )

    preview = TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(backup_data),
      strategy: :merge
    ).preview

    assert_equal 1, preview[:total_manga]
    assert_equal 1, preview[:mapped_manga]
    assert_equal 1, preview[:total_chapters]
    assert_equal 1, preview[:read_chapters]
  end

  def test_skip_strategy_does_not_update_existing
    # Create series and progress first
    backup_data = build_backup(
      source_id: 2131019126180322627,
      title: "Skip Strategy Manga",
      url: "/manga/skip-test",
      chapters: [
        { url: "/ch/1", name: "Chapter 1", number: 1.0, read: true }
      ]
    )

    # First import
    TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(backup_data),
      strategy: :merge
    ).perform

    # Second import with skip should not change anything
    result = TachiyomiImportService.new(
      user: @user,
      file: StringIO.new(backup_data),
      strategy: :skip
    ).perform

    assert result.success
    assert_equal 0, result.imported[:chapters]
  end

  private

  def build_backup(source_id:, title:, url:, chapters: [])
    tachi_chapters = chapters.map do |ch|
      Tachiyomi::BackupChapter.new(
        url: ch[:url],
        name: ch[:name],
        chapterNumber: ch[:number],
        read: ch[:read] || false
      )
    end

    backup = Tachiyomi::Backup.new(
      backupManga: [
        Tachiyomi::BackupManga.new(
          source: source_id,
          url: url,
          title: title,
          favorite: true,
          chapters: tachi_chapters
        )
      ],
      backupSources: [
        Tachiyomi::BackupSource.new(name: "Test Source", sourceId: source_id)
      ]
    )

    encoded = Tachiyomi::Backup.encode(backup)
    Zlib.gzip(encoded)
  end
end
