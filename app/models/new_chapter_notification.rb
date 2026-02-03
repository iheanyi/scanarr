# frozen_string_literal: true

class NewChapterNotification < ApplicationRecord
  belongs_to :user
  belongs_to :chapter

  scope :unread, -> { where(read: false) }
  scope :recent, -> { where("created_at > ?", 7.days.ago) }

  def mark_as_read!
    update!(read: true)
  end
end
