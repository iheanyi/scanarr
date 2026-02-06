# frozen_string_literal: true

module UI
  class FollowControlsComponent < BaseComponent
    # @param series [Series] The series being followed
    # @param user_follow [UserSeriesFollow, nil] Current user's follow record
    def initialize(series:, user_follow:)
      @series = series
      @user_follow = user_follow
      super()
    end

    private

    attr_reader :series, :user_follow
  end
end
