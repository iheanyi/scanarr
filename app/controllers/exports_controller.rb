class ExportsController < ApplicationController
  def show
    @preview = LibraryExportService.new(user: current_user).preview
  end

  def create
    data = LibraryExportService.new(user: current_user).perform

    send_data data,
              filename: "scanarr_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.scanarr",
              type: "application/gzip",
              disposition: "attachment"
  end

  def import_library
    unless params[:file].present?
      flash[:alert] = "Please select a .scanarr export file."
      redirect_to export_path
      return
    end

    file = params[:file]
    data = file.read
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

  private

  def import_summary(imported)
    parts = []
    parts << "#{imported[:library_series]} series" if imported[:library_series] > 0
    parts << "#{imported[:chapters]} chapters" if imported[:chapters] > 0
    parts << "#{imported[:progress]} progress entries" if imported[:progress] > 0
    parts << "#{imported[:follows]} follows" if imported[:follows] > 0
    parts.any? ? parts.join(", ") : "No new data imported."
  end
end
