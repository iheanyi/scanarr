require "test_helper"

class LibraryExportServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by!(email: "admin@scanarr.local")
  end

  def test_export_produces_gzipped_json
    result = LibraryExportService.new(user: @user).perform

    assert result.is_a?(String)
    assert result.b.start_with?("\x1f\x8b".b) # gzip magic bytes

    data = Zlib::GzipReader.new(StringIO.new(result)).read
    parsed = JSON.parse(data)

    assert_equal "scanarr_library_export", parsed["format"]
    assert_equal 1, parsed["version"]
    assert parsed["created_at"].present?
  end

  def test_export_includes_sources
    result = LibraryExportService.new(user: @user).perform
    parsed = parse_export(result)

    assert parsed["sources"].is_a?(Array)
    assert parsed["sources"].length > 0

    source = parsed["sources"].first
    assert source["key"].present?
    assert source["slug"].present?
  end

  def test_export_includes_library_series
    result = LibraryExportService.new(user: @user).perform
    parsed = parse_export(result)

    assert parsed["library_series"].is_a?(Array)
  end

  def test_export_includes_reading_progress
    result = LibraryExportService.new(user: @user).perform
    parsed = parse_export(result)

    assert parsed["reading_progress"].is_a?(Array)
  end

  def test_export_includes_follows
    result = LibraryExportService.new(user: @user).perform
    parsed = parse_export(result)

    assert parsed["follows"].is_a?(Array)
  end

  def test_preview_returns_counts
    preview = LibraryExportService.new(user: @user).preview

    assert preview[:sources].is_a?(Integer)
    assert preview[:library_series].is_a?(Integer)
    assert preview[:series].is_a?(Integer)
    assert preview[:chapters].is_a?(Integer)
    assert preview[:reading_progress].is_a?(Integer)
    assert preview[:follows].is_a?(Integer)
  end

  private

  def parse_export(result)
    data = Zlib::GzipReader.new(StringIO.new(result)).read
    JSON.parse(data)
  end
end
