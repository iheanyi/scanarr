require "test_helper"

class Admin::BackupsControllerTest < ActionDispatch::IntegrationTest
  def test_index_returns_success
    get admin_backups_path

    assert_response :success
  end

  def test_index_shows_stats_cards
    get admin_backups_path

    assert_response :success
    assert_includes @response.body, "Total Backups"
    assert_includes @response.body, "Complete"
    assert_includes @response.body, "Failed"
    assert_includes @response.body, "Total Size"
  end

  def test_index_shows_empty_state_when_no_backups
    get admin_backups_path

    assert_response :success
    assert_includes @response.body, "No backups yet"
  end

  def test_index_shows_backup_records
    BackupRecord.create!(
      filename: "test_backup.zip",
      backup_type: "manual",
      status: "complete",
      size: 1024
    )

    get admin_backups_path

    assert_response :success
    assert_includes @response.body, "test_backup.zip"
  end

  def test_create_enqueues_backup_job
    assert_difference "BackupRecord.count", 1 do
      post admin_create_backup_path
    end

    assert_redirected_to admin_backups_path

    record = BackupRecord.last
    assert_equal "manual", record.backup_type
    assert_equal "pending", record.status
  end

  def test_destroy_deletes_backup_record
    record = BackupRecord.create!(
      filename: "to_delete.zip",
      backup_type: "manual",
      status: "complete"
    )

    assert_difference "BackupRecord.count", -1 do
      delete admin_backup_path(record)
    end

    assert_redirected_to admin_backups_path
  end

  def test_download_redirects_when_file_missing
    record = BackupRecord.create!(
      filename: "missing.zip",
      path: "/nonexistent/path.zip",
      backup_type: "manual",
      status: "complete"
    )

    get admin_backup_download_path(record)

    assert_redirected_to admin_backups_path
    assert_equal "Backup file not found on disk.", flash[:alert]
  end

  def test_verify_redirects_when_file_missing
    record = BackupRecord.create!(
      filename: "missing.zip",
      path: "/nonexistent/path.zip",
      backup_type: "manual",
      status: "complete"
    )

    post admin_backup_verify_path(record)

    assert_redirected_to admin_backups_path
    assert_equal "Backup file not found on disk.", flash[:alert]
  end
end
