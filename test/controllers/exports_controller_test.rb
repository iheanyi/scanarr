require "test_helper"

class ExportsControllerTest < ActionDispatch::IntegrationTest
  def test_show_returns_success
    get export_path

    assert_response :success
    assert_includes @response.body, "Export Library"
    assert_includes @response.body, "Import Library"
  end

  def test_show_displays_preview_stats
    get export_path

    assert_response :success
    assert_includes @response.body, "Sources"
    assert_includes @response.body, "Library Series"
    assert_includes @response.body, "Chapters"
    assert_includes @response.body, "Reading Progress"
    assert_includes @response.body, "Follows"
  end

  def test_create_downloads_scanarr_file
    post export_path

    assert_response :success
    assert_equal "application/gzip", @response.media_type
    assert_match /scanarr_export_.*\.scanarr/, @response.headers["Content-Disposition"]
  end

  def test_create_produces_valid_gzipped_json
    post export_path

    data = Zlib::GzipReader.new(StringIO.new(@response.body)).read
    parsed = JSON.parse(data)

    assert_equal "scanarr_library_export", parsed["format"]
    assert_equal 1, parsed["version"]
    assert_kind_of Array, parsed["sources"]
    assert_kind_of Array, parsed["library_series"]
    assert_kind_of Array, parsed["reading_progress"]
    assert_kind_of Array, parsed["follows"]
  end

  def test_import_without_file_redirects_with_alert
    post import_library_path

    assert_redirected_to export_path
    assert_equal "Please select a .scanarr export file.", flash[:alert]
  end

  def test_import_with_valid_file_succeeds
    # First export, then import
    post export_path
    export_data = @response.body

    file = Rack::Test::UploadedFile.new(
      StringIO.new(export_data),
      "application/gzip",
      original_filename: "test.scanarr"
    )

    post import_library_path, params: { file: file, strategy: "skip" }

    assert_redirected_to export_path
    assert_match /Import complete/, flash[:notice]
  end
end
