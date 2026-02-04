# frozen_string_literal: true

module UI
  class MultiSelectComponent < BaseComponent
    def initialize(name:, options:, selected: [], label: nil, hint: nil, filter_placeholder: "Filter options", all_label: "All sources", max_chips: 4, **system_arguments)
      super(**system_arguments)
      @name = name
      @options = options
      @selected = Array(selected).map(&:to_s)
      @label = label
      @hint = hint
      @filter_placeholder = filter_placeholder
      @all_label = all_label
      @max_chips = max_chips
    end

    def wrapper_classes
      cn("space-y-2", system_arguments[:class])
    end

    def checkbox_name
      @name.to_s.ends_with?("[]") ? @name : "#{@name}[]"
    end

    def selected_options
      @options.select { |_label, value| @selected.include?(value.to_s) }
    end

    def panel_id
      "#{@name.to_s.gsub(/\[|\]/, "")}-panel"
    end

    def count_label
      return "None selected" if @selected.empty?
      return @all_label if @selected.length == @options.length

      "#{@selected.length} selected"
    end
  end
end
