# frozen_string_literal: true

class LibraryImportPreviewService
  SUPPORTED_VERSIONS = [ 1 ].freeze

  def initialize(data:, user:)
    @data = data
    @user = user
  end

  def preview
    parsed = parse_data

    library_series_data = parsed["library_series"] || []
    reading_progress_data = parsed["reading_progress"] || []
    follows_data = parsed["follows"] || []

    # Count totals
    total_series = library_series_data.size
    total_chapters = library_series_data.sum { |ls| (ls["series"] || []).sum { |s| (s["chapters"] || []).size } }
    total_progress = reading_progress_data.size
    total_follows = follows_data.size

    # Check what already exists
    existing_titles = LibrarySeries.where(
      canonical_title: library_series_data.map { |ls| ls["canonical_title"] }
    ).pluck(:canonical_title).to_set

    new_series = library_series_data.count { |ls| !existing_titles.include?(ls["canonical_title"]) }
    existing_series = library_series_data.count { |ls| existing_titles.include?(ls["canonical_title"]) }

    # Check source availability
    all_source_keys = library_series_data.flat_map { |ls|
      (ls["series"] || []).flat_map { |s|
        (s["source_mappings"] || []).map { |m| m["source_key"] }
      }
    }.uniq.compact

    available_sources = Source.where(key: all_source_keys).pluck(:key).to_set
    unavailable_source_keys = all_source_keys - available_sources.to_a

    # Build series list for display
    series_details = library_series_data.map { |ls|
      chapter_count = (ls["series"] || []).sum { |s| (s["chapters"] || []).size }
      sources = (ls["series"] || []).flat_map { |s|
        (s["source_mappings"] || []).map { |m| m["source_key"] }
      }.uniq.compact

      {
        title: ls["canonical_title"],
        exists: existing_titles.include?(ls["canonical_title"]),
        chapter_count: chapter_count,
        sources: sources,
        source_names: sources.map { |k| Source.find_by(key: k)&.name || k }
      }
    }

    {
      format: parsed["format"],
      version: parsed["version"],
      exported_at: parsed["exported_at"],
      total_library_series: total_series,
      total_chapters: total_chapters,
      total_progress: total_progress,
      total_follows: total_follows,
      new_series: new_series,
      existing_series: existing_series,
      available_sources: available_sources.size,
      unavailable_sources: unavailable_source_keys.size,
      unavailable_source_keys: unavailable_source_keys,
      series_details: series_details
    }
  end

  private

  def parse_data
    raw = if @data.is_a?(String) && @data.b.start_with?("\x1f\x8b".b)
      Zlib::GzipReader.new(StringIO.new(@data.b)).read
    elsif @data.is_a?(String)
      @data
    else
      raise "Unsupported import data format"
    end

    parsed = JSON.parse(raw)

    unless parsed["format"] == "scanarr_library_export"
      raise "Unknown export format: #{parsed['format']}"
    end

    unless SUPPORTED_VERSIONS.include?(parsed["version"])
      raise "Unsupported export version: #{parsed['version']}"
    end

    parsed
  end
end
