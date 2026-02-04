# frozen_string_literal: true

module UI
  class AutoSelectComponent < BaseComponent
    def initialize(form:, method:, options:, selected: nil, include_blank: nil, label: nil, hint: nil, size: :md, full_width: true, **system_arguments)
      super(**system_arguments)
      @form = form
      @method = method
      @options = options
      @selected = selected
      @include_blank = include_blank
      @label = label
      @hint = hint
      @size = size
      @full_width = full_width
    end

    def select_arguments
      attributes = system_arguments.dup
      attributes[:data] = select_data.merge(attributes.fetch(:data, {}))
      attributes
    end

    private

    def select_data
      { controller: "auto-submit", action: "change->auto-submit#submit" }
    end
  end
end
