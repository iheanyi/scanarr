module AdminDownloads
  module UpdateBroadcast
    private

    def broadcast_admin_download_update(file_asset)
      return unless file_asset

      Turbo::StreamsChannel.broadcast_replace_to(
        "admin_downloads",
        target: ActionView::RecordIdentifier.dom_id(file_asset),
        partial: "admin/downloads/download_row",
        locals: { download: file_asset.reload }
      )
    rescue StandardError => e
      Rails.logger.warn "#{self.class.name}: Failed to broadcast admin download update: #{e.message}"
    end
  end
end
