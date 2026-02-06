require "test_helper"

class LibraryImportServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by!(email: "admin@scanarr.local")
  end

  def test_import_from_gzipped_data
    export_data = LibraryExportService.new(user: @user).perform

    result = LibraryImportService.new(
      data: export_data,
      user: @user,
      strategy: :skip
    ).perform

    assert result.success
    assert result.errors.empty?
  end

  def test_import_from_raw_json
    raw_json = JSON.generate({
      "format" => "scanarr_library_export",
      "version" => 1,
      "library_series" => [],
      "reading_progress" => [],
      "follows" => []
    })

    result = LibraryImportService.new(
      data: raw_json,
      user: @user,
      strategy: :merge
    ).perform

    assert result.success
  end

  def test_import_rejects_unknown_format
    raw_json = JSON.generate({ "format" => "unknown", "version" => 1 })

    result = LibraryImportService.new(
      data: raw_json,
      user: @user,
      strategy: :merge
    ).perform

    assert_not result.success
    assert_includes result.errors.first, "Unknown export format"
  end

  def test_import_rejects_unsupported_version
    raw_json = JSON.generate({
      "format" => "scanarr_library_export",
      "version" => 999
    })

    result = LibraryImportService.new(
      data: raw_json,
      user: @user,
      strategy: :merge
    ).perform

    assert_not result.success
    assert_includes result.errors.first, "Unsupported export version"
  end

  def test_skip_strategy_does_not_overwrite_existing
    # Export first
    export_data = LibraryExportService.new(user: @user).perform

    initial_series_count = Series.count

    # Import with skip strategy
    result = LibraryImportService.new(
      data: export_data,
      user: @user,
      strategy: :skip
    ).perform

    assert result.success
    # Series count should stay the same since everything already exists
    assert_equal initial_series_count, Series.count
  end

  def test_merge_strategy_imports_new_data
    export_data = LibraryExportService.new(user: @user).perform

    result = LibraryImportService.new(
      data: export_data,
      user: @user,
      strategy: :merge
    ).perform

    assert result.success
  end
end
