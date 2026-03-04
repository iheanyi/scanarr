class OfflineLibraryController < ApplicationController
  before_action :require_local_downloads_enabled

  def show
  end
end
