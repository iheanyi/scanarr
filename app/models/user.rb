class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :chapter_progresses, dependent: :destroy
  has_many :user_series_follows, dependent: :destroy
  has_many :followed_library_series, through: :user_series_follows, source: :library_series
  has_many :new_chapter_notifications, dependent: :destroy
end
