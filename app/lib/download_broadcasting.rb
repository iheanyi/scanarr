module DownloadBroadcasting
  private

  def broadcast_admin_download_update(file_asset, log_prefix: self.class.name)
    return unless file_asset

    Turbo::StreamsChannel.broadcast_replace_to(
      "admin_downloads",
      target: ActionView::RecordIdentifier.dom_id(file_asset),
      partial: "admin/downloads/download_row",
      locals: { download: file_asset.reload }
    )
  rescue StandardError => e
    prefix = log_prefix ? "#{log_prefix}: " : ""
    Rails.logger.warn "#{prefix}Failed to broadcast admin download update: #{e.message}"
  end

  def broadcast_chapter_row_update(chapter:, series:, source:, log_prefix: self.class.name)
    return unless chapter && series && source

    chapter.reload
    latest_release = chapter.releases.includes(:file_asset).order(created_at: :desc).first

    Turbo::StreamsChannel.broadcast_replace_to(
      [ series, :downloads ],
      target: ActionView::RecordIdentifier.dom_id(chapter),
      partial: "series/chapter_row",
      locals: { chapter: chapter, source: source, series: series, progress: nil, latest_release: latest_release }
    )
  rescue StandardError => e
    prefix = log_prefix ? "#{log_prefix}: " : ""
    Rails.logger.warn "#{prefix}Failed to broadcast chapter update: #{e.message}"
  end
end
