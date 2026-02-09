# frozen_string_literal: true

class TachiyomiImportJob < ApplicationJob
  queue_as :default

  def perform(user_id, file_path, strategy: "merge")
    user = User.find(user_id)
    strategy = strategy.to_sym

    broadcast_status(user, "importing", "Importing Mihon backup...")

    result = TachiyomiImportService.new(
      user: user,
      file: file_path,
      strategy: strategy
    ).perform

    if result.success
      summary = build_summary(result)
      broadcast_status(user, "complete", summary)
    else
      error_msg = "Import had errors: #{result.errors.first(3).join('; ')}"
      broadcast_status(user, "error", error_msg)
    end
  ensure
    # Clean up the temp file
    File.delete(file_path) if file_path && File.exist?(file_path)
  end

  private

  def broadcast_status(user, status, message)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ user, :tachiyomi_import ],
      target: "tachiyomi-import-status",
      html: render_status_html(status, message)
    )
  end

  def render_status_html(status, message)
    icon, color = case status
    when "importing"
      [ "⏳", "text-warning" ]
    when "complete"
      [ "✓", "text-success" ]
    when "error"
      [ "✗", "text-danger" ]
    end

    <<~HTML
      <div id="tachiyomi-import-status" class="flex items-center gap-2 p-3 rounded-lg bg-surface-2">
        <span class="#{color} text-lg">#{icon}</span>
        <span class="text-sm text-foreground">#{ERB::Util.html_escape(message)}</span>
      </div>
    HTML
  end

  def build_summary(result)
    parts = []
    parts << "#{result.imported[:series]} series" if result.imported[:series].to_i > 0
    parts << "#{result.imported[:chapters]} chapters" if result.imported[:chapters].to_i > 0
    parts << "#{result.imported[:progress]} progress" if result.imported[:progress].to_i > 0
    parts << "#{result.imported[:follows]} follows" if result.imported[:follows].to_i > 0
    parts << "#{result.imported[:tracking]} trackers" if result.imported[:tracking].to_i > 0

    summary = parts.any? ? "Import complete: #{parts.join(', ')}" : "No new data imported."

    if result.unmapped_sources.any?
      names = result.unmapped_sources.map { |s| s[:name] }.first(5).join(", ")
      summary += " (#{result.unmapped_sources.size} unmapped sources: #{names})"
    end

    summary
  end
end
