class CancelAllDownloadsJob < ApplicationJob
  queue_as :default

  def perform(series_id, source_id)
    series = Series.find(series_id)
    source = Source.find(source_id)

    chapters = series.chapters.where(source: source).includes(releases: { file_asset: :pages })
    cancelled = 0

    chapters.find_each do |chapter|
      chapter.releases.each do |release|
        file_asset = release.file_asset
        next unless file_asset
        next unless file_asset.download_status.in?(%w[queued pending downloading])

        # Purge any partially downloaded files
        file_asset.archive.purge if file_asset.archive.attached?
        file_asset.pages.each { |page| page.image.purge if page.image.attached? }
        file_asset.pages.destroy_all

        # Reset status
        file_asset.update!(
          download_status: "cancelled",
          pages_downloaded: 0,
          pages_expected: nil,
          download_error: nil
        )
        cancelled += 1

        # Broadcast update for this chapter
        broadcast_chapter_update(series, chapter)
      end
    end

    Rails.logger.info "CancelAllDownloadsJob: Cancelled #{cancelled} downloads for #{series.canonical_title}"
  end

  private

  def broadcast_chapter_update(series, chapter)
    # Get fresh data for the partial
    chapter.reload
    latest_release = chapter.releases.max_by(&:created_at)
    file_asset = latest_release&.file_asset
    source = chapter.source

    Turbo::StreamsChannel.broadcast_replace_to(
      [series, :downloads],
      target: ActionView::RecordIdentifier.dom_id(chapter),
      partial: "series/chapter_row",
      locals: {
        chapter: chapter,
        source: source,
        series: series,
        progress: nil
      }
    )
  rescue => e
    Rails.logger.warn "Failed to broadcast chapter update: #{e.message}"
  end
end
