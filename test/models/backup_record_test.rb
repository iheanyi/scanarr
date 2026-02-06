require "test_helper"

class BackupRecordTest < ActiveSupport::TestCase
  def test_valid_record
    record = BackupRecord.new(
      filename: "test.zip",
      backup_type: "manual",
      status: "complete",
      size: 1024
    )

    assert record.valid?
  end

  def test_requires_filename
    record = BackupRecord.new(backup_type: "manual", status: "complete")

    assert_not record.valid?
    assert_includes record.errors[:filename], "can't be blank"
  end

  def test_requires_valid_backup_type
    record = BackupRecord.new(filename: "test.zip", backup_type: "invalid", status: "complete")

    assert_not record.valid?
    assert_includes record.errors[:backup_type], "is not included in the list"
  end

  def test_requires_valid_status
    record = BackupRecord.new(filename: "test.zip", backup_type: "manual", status: "invalid")

    assert_not record.valid?
    assert_includes record.errors[:status], "is not included in the list"
  end

  def test_human_size
    record = BackupRecord.new(size: 1_048_576)
    assert_equal "1 MB", record.human_size
  end

  def test_human_size_nil_when_no_size
    record = BackupRecord.new(size: nil)
    assert_nil record.human_size
  end

  def test_file_exists_false_when_no_path
    record = BackupRecord.new(path: nil)
    assert_not record.file_exists?
  end

  def test_file_exists_false_when_path_missing
    record = BackupRecord.new(path: "/nonexistent/file.zip")
    assert_not record.file_exists?
  end

  def test_scopes
    BackupRecord.create!(filename: "complete.zip", backup_type: "manual", status: "complete", created_at: 1.day.ago)
    BackupRecord.create!(filename: "failed.zip", backup_type: "scheduled", status: "failed", created_at: 2.days.ago)

    assert_equal 1, BackupRecord.complete.count
    assert_equal 1, BackupRecord.failed.count
    assert_equal "complete.zip", BackupRecord.recent.first.filename
  end
end
