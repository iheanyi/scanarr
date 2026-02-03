require "nanoid"

module HasPublicId
  extend ActiveSupport::Concern

  PUBLIC_ID_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
  PUBLIC_ID_LENGTH = 12
  MAX_RETRY = 1000

  included do
    before_validation :set_public_id, on: :create
    validates :public_id, presence: true, uniqueness: true
  end

  class_methods do
    def generate_public_id
      Nanoid.generate(size: PUBLIC_ID_LENGTH, alphabet: PUBLIC_ID_ALPHABET)
    end

    # Find a record by its public_id, raising RecordNotFound if not found
    def find_by_public_id!(public_id)
      find_by!(public_id: public_id)
    end

    # Find a record by its public_id, returning nil if not found
    def find_by_public_id(public_id)
      find_by(public_id: public_id)
    end
  end

  # Override to_param for URL generation
  # This makes Rails use public_id instead of id in URLs
  def to_param
    public_id
  end

  private

  def set_public_id
    return if public_id.present?

    MAX_RETRY.times do
      self.public_id = self.class.generate_public_id
      return unless self.class.exists?(public_id: public_id)
    end

    raise "Failed to generate a unique public_id after #{MAX_RETRY} attempts"
  end
end
