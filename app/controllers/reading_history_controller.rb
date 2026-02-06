# frozen_string_literal: true

class ReadingHistoryController < ApplicationController
  def index
    @progresses = current_user.chapter_progresses
                              .includes(chapter: [ :source, { series: { cover_attachment: :blob } } ])
                              .order(progressed_at: :desc)

    @progresses = @progresses.where(status: params[:status]) if params[:status].present?
    @progresses = @progresses.page(params[:page]).per(30)
  end
end
