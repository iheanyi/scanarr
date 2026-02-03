class ChapterProgress < ApplicationRecord
  belongs_to :user
  belongs_to :chapter

  validates :page_index, :page_count, :status, :progressed_at, presence: true
  validates :chapter_id, uniqueness: { scope: :user_id }
  validates :status, inclusion: { in: %w[in_progress completed] }
end
