# frozen_string_literal: true

module UI
  class FollowPreferencesComponent < BaseComponent
    def initialize(user_follow:)
      @user_follow = user_follow
      super()
    end

    private

    attr_reader :user_follow
  end
end
