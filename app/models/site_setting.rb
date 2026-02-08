class SiteSetting < ApplicationRecord
  def self.instance
    first_or_create!
  end

  def self.registration_enabled?
    instance.registration_enabled
  end
end
