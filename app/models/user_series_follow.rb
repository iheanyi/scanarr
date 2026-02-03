class UserSeriesFollow < ApplicationRecord
  belongs_to :user
  belongs_to :library_series

  enum :download_policy, { notify_only: 0, auto_download: 1 }

  validates :user_id, uniqueness: { scope: :library_series_id }

  # Helper method to check if auto-download is enabled
  def auto_download?
    download_policy == "auto_download"
  end
end
