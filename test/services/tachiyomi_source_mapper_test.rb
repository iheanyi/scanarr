require "test_helper"
require_relative "../../lib/tachiyomi/parser"

class TachiyomiSourceMapperTest < ActiveSupport::TestCase
  def test_scanarr_key_for_known_source
    assert_equal "mangadex", TachiyomiSourceMapper.scanarr_key_for(2499283573021220255)
  end

  def test_scanarr_key_for_legacy_hardcoded_id
    assert_equal "weeb_central", TachiyomiSourceMapper.scanarr_key_for(9)
  end

  def test_scanarr_key_for_dead_source_maps_to_replacement
    # MangaLife (shut down) maps to weeb_central
    assert_equal "weeb_central", TachiyomiSourceMapper.scanarr_key_for(7798162483793432927)
  end

  def test_scanarr_key_for_alt_domain_variant
    # comick.fun (DMCA'd) maps to comick
    assert_equal "comick", TachiyomiSourceMapper.scanarr_key_for(2971557565147974499)
  end

  def test_scanarr_key_for_unknown_source_returns_nil
    assert_nil TachiyomiSourceMapper.scanarr_key_for(9999999999)
  end

  def test_tachiyomi_id_for_known_key
    assert_equal 2499283573021220255, TachiyomiSourceMapper.tachiyomi_id_for("mangadex")
  end

  def test_tachiyomi_id_for_unknown_key_returns_nil
    assert_nil TachiyomiSourceMapper.tachiyomi_id_for("nonexistent")
  end

  def test_known_returns_true_for_mapped_source
    assert TachiyomiSourceMapper.known?(2499283573021220255)
  end

  def test_known_returns_true_for_future_source
    # manga_plus is a future source
    assert TachiyomiSourceMapper.known?(1998944621602463790)
  end

  def test_known_returns_false_for_unknown_source
    refute TachiyomiSourceMapper.known?(123)
  end

  def test_future_source_name
    assert_equal "manga_plus", TachiyomiSourceMapper.future_source_name(1998944621602463790)
  end

  def test_future_source_name_returns_nil_for_mapped_source
    assert_nil TachiyomiSourceMapper.future_source_name(2499283573021220255)
  end

  def test_unmapped_sources_from_backup
    backup = Tachiyomi::Backup.new(
      backupManga: [
        Tachiyomi::BackupManga.new(source: 2499283573021220255, title: "Mapped"),
        Tachiyomi::BackupManga.new(source: 123456789, title: "Unmapped")
      ]
    )

    unmapped = TachiyomiSourceMapper.unmapped_sources(backup)
    assert_includes unmapped, 123456789
    refute_includes unmapped, 2499283573021220255
  end

  def test_source_name_from_backup
    backup = Tachiyomi::Backup.new(
      backupSources: [
        Tachiyomi::BackupSource.new(name: "MangaDex", sourceId: 2499283573021220255)
      ]
    )

    assert_equal "MangaDex", TachiyomiSourceMapper.source_name_from_backup(backup, 2499283573021220255)
    assert_nil TachiyomiSourceMapper.source_name_from_backup(backup, 999)
  end
end
