require "tempfile"
require "zip"

class ChapterPackager
  def initialize(file_asset)
    @file_asset = file_asset
  end

  def package!
    pages = @file_asset.pages.includes(image_attachment: :blob).order(:position).to_a
    return if pages.empty?

    buffer = Zip::OutputStream.write_buffer do |zip|
      pages.each do |page|
        filename = page.image.filename.to_s
        zip.put_next_entry(filename)
        page.image.open do |image_io|
          IO.copy_stream(image_io, zip)
        end
      end
    end

    buffer.rewind
    attach_options = {
      io: buffer,
      filename: "chapter-#{@file_asset.release.public_id}.cbz",
      content_type: "application/vnd.comicbook+zip"
    }
    key = archive_key
    attach_options[:key] = key if key.present?

    @file_asset.archive.attach(attach_options)
  end

  private

  def archive_key
    return "#{@file_asset.path}/chapter.cbz" if @file_asset.path.present?

    chapter = @file_asset.release.chapter
    source = @file_asset.release.source || chapter.source || chapter.series.primary_source
    return nil unless source

    LibraryPathBuilder.new(series: chapter.series, source: source).archive_path(chapter)
  end
end
