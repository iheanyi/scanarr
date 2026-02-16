class UserOfflineManifestEntry < ApplicationRecord
  belongs_to :user
  belongs_to :chapter

  enum :status, {
    pinned: "pinned",
    downloading: "downloading",
    complete: "complete",
    failed: "failed"
  }, default: :pinned, validate: true

  validates :chapter_id, uniqueness: { scope: :user_id }
end
