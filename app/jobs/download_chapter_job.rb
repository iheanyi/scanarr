class DownloadChapterJob < ApplicationJob
  queue_as :default

  def perform(
    chapter_url,
    source_key: "weeb_central",
    series_title:,
    source_series_id: nil,
    chapter_number:,
    chapter_title: nil,
    language: nil,
    group: nil,
    max_pages: nil,
    adapter: nil,
    http: nil
  )
    adapter ||= adapter_for(source_key)
    http ||= HttpClient.new(config: adapter.config)

    source = Source.find_or_create_by!(key: source_key) do |record|
      record.name = source_key.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
      record.base_url = adapter.config["base_url"]
    end

    series = find_or_create_series(source: source, series_title: series_title, source_series_id: source_series_id)

    chapter = Chapter.find_or_create_by!(
      series: series,
      chapter_number: chapter_number,
      language: language,
      group: group
    ) do |record|
      record.title = chapter_title
      record.source = source
    end
    if chapter_title && chapter.title != chapter_title
      chapter.update!(title: chapter_title)
    end

    release = chapter.releases.create!(
      source: source,
      format: "pages",
      source_url: chapter_url
    )
    file_asset = release.create_file_asset!(
      format: "pages",
      download_status: "downloading",
      pages_downloaded: 0,
      download_error: nil
    )

    downloader = ChapterDownloader.new(adapter: adapter, http: http)

    Dir.mktmpdir("scanarr-chapter-") do |dir|
      files = downloader.download(chapter_url, output_dir: dir, max_pages: max_pages)
      file_asset.update!(pages_expected: files.size)
      files.each_with_index do |path, idx|
        page = file_asset.pages.create!(position: idx + 1)
        File.open(path, "rb") do |io|
          page.image.attach(io: io, filename: File.basename(path))
        end
        file_asset.update!(pages_downloaded: idx + 1)
      end
    end

    file_asset.update!(
      page_count: file_asset.pages.count,
      download_status: "complete",
      pages_downloaded: file_asset.pages.count
    )
    file_asset.archive.purge if file_asset.archive.attached?
    ChapterPackager.new(file_asset).package!

    release
  rescue StandardError => error
    file_asset&.update!(download_status: "failed", download_error: "#{error.class}: #{error.message}")
    raise
  end

  private

  def adapter_for(source_key)
    case source_key.to_s
    when "weeb_central"
      WeebCentral::Adapter.new(config: Rails.configuration.scraper_sources.fetch("weeb_central", {}))
    when "mangadex"
      Mangadex::Adapter.new(config: Rails.configuration.scraper_sources.fetch("mangadex", {}))
    else
      raise ArgumentError, "Unknown source_key #{source_key.inspect}"
    end
  end

  def find_or_create_series(source:, series_title:, source_series_id:)
    if source_series_id.present?
      series_source = SeriesSource.find_by(source: source, source_series_id: source_series_id)
      return series_source.series if series_source
    end

    series_source = SeriesSource.joins(:series)
                                .where(source: source, series: { canonical_title: series_title })
                                .first
    if series_source
      if source_series_id.present? && series_source.source_series_id != source_series_id
        series_source.update!(source_series_id: source_series_id)
      end
      return series_source.series
    end

    series = Series.create!(canonical_title: series_title)
    SeriesSource.create!(series: series, source: source, source_series_id: source_series_id)
    series
  end
end
