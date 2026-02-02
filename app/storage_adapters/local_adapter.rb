require "fileutils"

class LocalAdapter
  attr_reader :root

  def initialize(root:)
    @root = root
  end

  def chapter_dir(source_key:, chapter_id:)
    path = File.join(root, source_key.to_s, "chapters", chapter_id.to_s)
    FileUtils.mkdir_p(path)
    path
  end
end

module StorageAdapters
  LocalAdapter = ::LocalAdapter
end
