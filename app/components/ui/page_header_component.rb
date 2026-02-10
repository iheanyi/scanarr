# frozen_string_literal: true

require_relative "base_component"

module UI
  class PageHeaderComponent < BaseComponent
    renders_one :actions
    renders_one :breadcrumb
    renders_one :description_content

    def initialize(title:, description: nil, breadcrumb_text: nil, **system_arguments)
      super(**system_arguments)
      @title = title
      @description = description
      @breadcrumb_text = breadcrumb_text
    end

    private

    attr_reader :title, :description, :breadcrumb_text
  end
end
