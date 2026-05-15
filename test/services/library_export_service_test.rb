require "test_helper"

class LibraryExportServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
  end

  def test_export_produces_gzipped_json
    result = LibraryExportService.new(user: @user).perform

    assert_kind_of String, result
    assert result.b.start_with?("\x1f\x8b".b) # gzip magic bytes

    data = Zlib::GzipReader.new(StringIO.new(result)).read
    parsed = JSON.parse(data)

    assert_equal "scanarr_library_export", parsed["format"]
    assert_equal 1, parsed["version"]
    assert_predicate parsed["created_at"], :present?
  end

  def test_export_includes_sources
    result = LibraryExportService.new(user: @user).perform
    parsed = parse_export(result)

    assert_kind_of Array, parsed["sources"]
    assert_operator parsed["sources"].length, :>, 0

    source = parsed["sources"].first

    assert_predicate source["key"], :present?
    assert_predicate source["slug"], :present?
  end

  def test_export_includes_library_series
    result = LibraryExportService.new(user: @user).perform
    parsed = parse_export(result)

    assert_kind_of Array, parsed["library_series"]
  end

  def test_export_includes_reading_progress
    result = LibraryExportService.new(user: @user).perform
    parsed = parse_export(result)

    assert_kind_of Array, parsed["reading_progress"]
  end

  def test_export_includes_follows
    result = LibraryExportService.new(user: @user).perform
    parsed = parse_export(result)

    assert_kind_of Array, parsed["follows"]
  end

  def test_preview_returns_counts
    preview = LibraryExportService.new(user: @user).preview

    assert_kind_of Integer, preview[:sources]
    assert_kind_of Integer, preview[:library_series]
    assert_kind_of Integer, preview[:series]
    assert_kind_of Integer, preview[:chapters]
    assert_kind_of Integer, preview[:reading_progress]
    assert_kind_of Integer, preview[:follows]
  end

  private

  def parse_export(result)
    data = Zlib::GzipReader.new(StringIO.new(result)).read
    JSON.parse(data)
  end
end
