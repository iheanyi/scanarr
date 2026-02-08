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
    @file_asset.archive.attach(
      io: buffer,
      filename: "chapter-#{@file_asset.release.public_id}.cbz",
      content_type: "application/vnd.comicbook+zip"
    )
  end
end
