class OfflineManifestsController < ApplicationController
  VALID_SYNC_STATUSES = %w[pinned downloading complete failed].freeze
  before_action :require_local_downloads_enabled

  def index
    entries = current_user.offline_manifest_entries
                         .includes(chapter: [ :series, :source ])
                         .order(updated_at: :desc)

    render json: {
      entries: entries.map { |entry| serialize_entry(entry) },
      synced_at: Time.current.iso8601
    }
  end

  def sync
    synced_entries = []

    sync_entries_params.each do |entry_params|
      chapter = Chapter.find_by(public_id: entry_params[:chapter_public_id].to_s)
      next unless chapter

      status = normalized_status(entry_params[:status])
      next unless status

      entry = current_user.offline_manifest_entries.find_or_initialize_by(chapter: chapter)
      entry.status = status
      entry.last_synced_at = parsed_time(entry_params[:last_synced_at]) || Time.current
      entry.completed_at = Time.current if status == "complete"
      entry.last_error = entry_params[:last_error].presence
      entry.last_error = nil if status == "complete"
      entry.save!

      synced_entries << serialize_entry(entry)
    end

    render json: {
      synced: synced_entries.size,
      entries: synced_entries,
      synced_at: Time.current.iso8601
    }
  rescue ActionController::ParameterMissing
    render json: { error: "entries parameter is required" }, status: :unprocessable_entity
  end

  private

  def sync_entries_params
    params.require(:entries).map do |entry|
      entry_params = if entry.is_a?(ActionController::Parameters)
        entry
      else
        ActionController::Parameters.new(entry.to_h)
      end

      entry_params.permit(:chapter_public_id, :status, :last_synced_at, :last_error)
    end
  end

  def normalized_status(raw_status)
    status = raw_status.to_s
    return status if VALID_SYNC_STATUSES.include?(status)

    nil
  end

  def parsed_time(raw_time)
    return nil if raw_time.blank?

    Time.zone.parse(raw_time.to_s)
  rescue ArgumentError
    nil
  end

  def serialize_entry(entry)
    chapter = entry.chapter
    source = chapter.source || chapter.releases.includes(:source).order(created_at: :desc).first&.source

    {
      id: entry.id,
      chapter_id: chapter.id,
      chapter_public_id: chapter.public_id,
      chapter_number: chapter.chapter_number,
      chapter_title: chapter.title,
      series_slug: chapter.series.to_param,
      source_slug: source&.slug,
      status: entry.status,
      last_error: entry.last_error,
      last_synced_at: entry.last_synced_at&.iso8601,
      completed_at: entry.completed_at&.iso8601,
      updated_at: entry.updated_at.iso8601
    }
  end
end
