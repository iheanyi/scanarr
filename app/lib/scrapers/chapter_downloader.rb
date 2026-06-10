require "fileutils"
require "uri"

module Scrapers
  class ChapterDownloader
    def initialize(adapter:, http: HttpClient.new(config: adapter.config))
      @adapter = adapter
      @http = http
    end

    def download(chapter_url, output_dir:, max_pages: nil)
      pages = @adapter.pages(chapter_url)
      pages = pages.first(max_pages) if max_pages

      FileUtils.mkdir_p(output_dir)

      pages.each_with_index.map do |page, idx|
        response = @http.get(page.url)
        unless response.status.to_i == 200
          raise "Failed to download #{page.url} (status #{response.status})"
        end

        index = page.index || idx + 1
        ext = extension_for(page.url, page.mime_type, response.headers["content-type"])
        filename = format("%03d%s", index, ext)
        path = File.join(output_dir, filename)
        File.binwrite(path, response.body.to_s)
        path
      end
    end

    private

    def extension_for(url, mime_type, response_type)
      ext = File.extname(URI.parse(url).path)
      return ext unless ext.nil? || ext.empty?

      type = [ mime_type, response_type ].compact.join(" ")
      return ".png" if type.match?(/png/i)
      return ".webp" if type.match?(/webp/i)
      return ".jpg" if type.match?(/jpe?g/i)

      ".bin"
    rescue URI::InvalidURIError
      ".bin"
    end
  end
end
