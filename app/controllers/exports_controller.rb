class ExportsController < ApplicationController
  def show
    @preview = LibraryExportService.new(user: current_user).preview
    @tachiyomi_preview = TachiyomiExportService.new(user: current_user).preview
  end

  def create
    data = LibraryExportService.new(user: current_user).perform

    send_data data,
              filename: "scanarr_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.scanarr",
              type: "application/gzip",
              disposition: "attachment"
  end

  def preview_library
    unless params[:file].present?
      flash[:alert] = "Please select a .scanarr export file."
      redirect_to export_path
      return
    end

    # Save uploaded file to tmp so it persists across the preview → import flow
    tmp_dir = Rails.root.join("tmp", "imports")
    FileUtils.mkdir_p(tmp_dir)
    tmp_path = tmp_dir.join("#{SecureRandom.hex}.scanarr").to_s
    File.open(tmp_path, "wb") { |f| f.write(params[:file].read) }
    session[:library_import_file] = tmp_path

    data = File.read(tmp_path)
    @preview = LibraryImportPreviewService.new(data: data, user: current_user).preview
    @strategy = params[:strategy]&.to_s || "merge"

    render :preview_library, status: :unprocessable_entity
  rescue => e
    flash[:alert] = "Could not parse export file: #{e.message}"
    cleanup_library_import_file
    redirect_to export_path
  end

  def import_library
    # Support both direct file upload and temp file from preview flow
    if params[:file].present?
      data = params[:file].read
    elsif session[:library_import_file].present?
      tmp_path = session[:library_import_file]
      unless File.exist?(tmp_path)
        flash[:alert] = "Preview expired. Please upload the file again."
        redirect_to export_path
        return
      end
      data = File.read(tmp_path)
      # Clean up temp file and session
      File.delete(tmp_path) if File.exist?(tmp_path)
      session.delete(:library_import_file)
    else
      flash[:alert] = "Please select a .scanarr export file."
      redirect_to export_path
      return
    end

    strategy = params[:strategy]&.to_sym || :merge

    result = LibraryImportService.new(
      data: data,
      user: current_user,
      strategy: strategy
    ).perform

    if result.success
      flash[:notice] = "Import complete! #{import_summary(result.imported)}"
    else
      flash[:alert] = "Import had errors: #{result.errors.first(3).join('; ')}"
    end

    redirect_to export_path
  end

  def preview_tachiyomi
    unless params[:file].present?
      flash[:alert] = "Please select a .tachibk or .proto.gz file."
      redirect_to export_path
      return
    end

    # Save uploaded file to tmp so it persists across the preview → import flow
    tmp_dir = Rails.root.join("tmp", "imports")
    FileUtils.mkdir_p(tmp_dir)
    tmp_path = tmp_dir.join("#{SecureRandom.hex}.tachibk").to_s
    File.open(tmp_path, "wb") { |f| f.write(params[:file].read) }
    session[:tachiyomi_import_file] = tmp_path

    file = File.open(tmp_path, "rb")
    @preview = TachiyomiImportService.new(user: current_user, file: file).preview
    file.close

    render :preview_tachiyomi, status: :unprocessable_entity
  rescue => e
    flash[:alert] = "Could not parse backup file: #{e.message}"
    cleanup_temp_import_file
    redirect_to export_path
  end

  def import_tachiyomi
    # Support both direct file upload and temp file from preview flow
    if params[:file].present?
      # Save uploaded file to tmp for the background job
      tmp_dir = Rails.root.join("tmp", "imports")
      FileUtils.mkdir_p(tmp_dir)
      tmp_path = tmp_dir.join("#{SecureRandom.hex}.tachibk").to_s
      File.open(tmp_path, "wb") { |f| f.write(params[:file].read) }
    elsif session[:tachiyomi_import_file].present?
      tmp_path = session[:tachiyomi_import_file]
      unless File.exist?(tmp_path)
        flash[:alert] = "Preview expired. Please upload the file again."
        redirect_to export_path
        return
      end
      # Clear session but don't delete the file — the job will clean it up
      session.delete(:tachiyomi_import_file)
    else
      flash[:alert] = "Please select a .tachibk or .proto.gz file."
      redirect_to export_path
      return
    end

    strategy = params[:strategy] || "merge"

    TachiyomiImportJob.perform_later(current_user.id, tmp_path, strategy: strategy)

    flash[:notice] = "Mihon import started in the background. You'll see progress below."
    redirect_to export_path
  end

  def export_tachiyomi
    data = TachiyomiExportService.new(user: current_user).perform

    send_data data,
              filename: "scanarr_#{Time.current.strftime('%Y-%m-%d_%H-%M')}.tachibk",
              type: "application/gzip",
              disposition: "attachment"
  end

  private

  def cleanup_library_import_file
    if session[:library_import_file].present?
      File.delete(session[:library_import_file]) if File.exist?(session[:library_import_file])
      session.delete(:library_import_file)
    end
  end

  def cleanup_temp_import_file
    if session[:tachiyomi_import_file].present?
      File.delete(session[:tachiyomi_import_file]) if File.exist?(session[:tachiyomi_import_file])
      session.delete(:tachiyomi_import_file)
    end
  end

  def import_summary(imported)
    parts = []
    parts << "#{imported[:library_series]} series" if imported[:library_series].to_i > 0
    parts << "#{imported[:chapters]} chapters" if imported[:chapters].to_i > 0
    parts << "#{imported[:progress]} progress entries" if imported[:progress].to_i > 0
    parts << "#{imported[:follows]} follows" if imported[:follows].to_i > 0
    parts.any? ? parts.join(", ") : "No new data imported."
  end

  def tachiyomi_import_summary(result)
    parts = []
    parts << "#{result.imported[:series]} series" if result.imported[:series].to_i > 0
    parts << "#{result.imported[:chapters]} chapters" if result.imported[:chapters].to_i > 0
    parts << "#{result.imported[:progress]} progress entries" if result.imported[:progress].to_i > 0
    parts << "#{result.imported[:follows]} follows" if result.imported[:follows].to_i > 0
    parts << "#{result.imported[:tracking]} trackers" if result.imported[:tracking].to_i > 0

    summary = parts.any? ? parts.join(", ") : "No new data imported."

    if result.unmapped_sources.any?
      names = result.unmapped_sources.map { |s| s[:name] }.first(5).join(", ")
      summary += " (#{result.unmapped_sources.size} unmapped sources: #{names})"
    end

    summary
  end
end
