class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable

  has_many :chapter_progresses, dependent: :destroy
  has_many :user_series_follows, dependent: :destroy
  has_many :followed_library_series, through: :user_series_follows, source: :library_series
end

