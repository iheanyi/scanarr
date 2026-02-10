# frozen_string_literal: true

require "zlib"
require_relative "backup_pb"

module Tachiyomi
  class Parser
    GZIP_MAGIC = "\x1f\x8b".b

    def parse(file_or_path)
      raw = case file_or_path
      when String then File.binread(file_or_path)
      when IO, StringIO, Tempfile, ActionDispatch::Http::UploadedFile
              file_or_path.rewind if file_or_path.respond_to?(:rewind)
              file_or_path.read
      else
              raise ArgumentError, "Expected a file path (String), IO, or UploadedFile"
      end

      data = gzipped?(raw) ? Zlib.gunzip(raw) : raw
      Tachiyomi::Backup.decode(data)
    end

    private

    def gzipped?(data)
      data.bytesize >= 2 && data.byteslice(0, 2) == GZIP_MAGIC
    end
  end
end
