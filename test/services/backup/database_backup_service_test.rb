require "test_helper"
require "rbconfig"
require "timeout"

class Backup::DatabaseBackupServiceTest < ActiveSupport::TestCase
  test "streams a database dump while draining verbose stderr" do
    with_dump_command('STDERR.write("warning" * 100_000); STDOUT.write("SELECT 1;\n" * 100_000)') do |service, directory|
      output = directory.join("database.sql.gz")

      Timeout.timeout(15) { service.send(:dump_database, output) }

      assert_equal "SELECT 1;\n" * 100_000, Zlib::GzipReader.open(output.to_s, &:read)
    end
  end

  test "reports a failed dump with a bounded diagnostic tail" do
    with_dump_command('STDOUT.write("partial dump"); STDERR.write("x" * 100_000 + "dump failed"); exit 1') do |service, directory|
      error = assert_raises(RuntimeError) do
        Timeout.timeout(15) { service.send(:dump_database, directory.join("database.sql.gz")) }
      end

      assert_match(/pg_dump failed: .*dump failed\z/, error.message)
      assert_operator error.message.bytesize, :<=, 516
    end
  end

  test "exports compatible blob metadata without per-blob attachment queries" do
    series = 5.times.map do |index|
      Series.create!(canonical_title: "Backup cover #{index}").tap do |record|
        record.cover.attach(io: StringIO.new("cover #{index}"), filename: "cover-#{index}.jpg", content_type: "image/jpeg")
      end
    end

    Dir.mktmpdir("backup-metadata-test") do |directory|
      output = File.join(directory, "active_storage_blobs.json")
      assert_queries_at_most(3) do
        Backup::DatabaseBackupService.new.send(:export_blob_metadata, output)
      end

      metadata = JSON.parse(File.read(output))
      series.each do |record|
        blob = record.cover.blob
        entry = metadata.find { |item| item.fetch("key") == blob.key }

        assert_equal blob.filename.to_s, entry.fetch("filename")
        assert_equal blob.byte_size, entry.fetch("byte_size")
        assert_equal blob.checksum, entry.fetch("checksum")
        assert_equal blob.service_name, entry.fetch("service_name")
        assert_equal [ { "record_type" => "Series", "record_id" => record.id, "name" => "cover" } ], entry.fetch("attachments")
      end
    end
  end

  private

  def with_dump_command(body)
    Dir.mktmpdir("backup-dump-test") do |directory|
      directory = Pathname.new(directory)
      command = directory.join("pg_dump")
      command.write("#!#{RbConfig.ruby}\n#{body}\n")
      command.chmod(0o700)
      service = Backup::DatabaseBackupService.new
      service.define_singleton_method(:pg_dump_path) { command.to_s }
      yield service, directory
    end
  end
end
