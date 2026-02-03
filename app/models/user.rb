class User < ApplicationRecord
  # Simple user model for storing progress/follows
  # Authentication is handled by HTTP Basic Auth at the controller level

  has_many :chapter_progresses, dependent: :destroy
  has_many :user_series_follows, dependent: :destroy
  has_many :followed_library_series, through: :user_series_follows, source: :library_series
  has_many :new_chapter_notifications, dependent: :destroy

  validates :email, presence: true, uniqueness: true
end
