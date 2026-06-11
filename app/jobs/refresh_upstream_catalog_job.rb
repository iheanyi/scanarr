# frozen_string_literal: true

# Daily mirror of the keiyoushi extensions index into upstream_sources.
# A failed fetch leaves all local state untouched.
class RefreshUpstreamCatalogJob < ApplicationJob
  queue_as :default

  def perform
    result = Sources::UpstreamCatalogService.new.call
    Rails.logger.info "[RefreshUpstreamCatalogJob] upserted #{result.upserted}, skipped #{result.skipped}"
  rescue Sources::UpstreamCatalogService::FetchError, SocketError, Timeout::Error => e
    Rails.logger.warn "[RefreshUpstreamCatalogJob] fetch failed, keeping existing catalog: #{e.message}"
  end
end
