# frozen_string_literal: true

module UI
  class MultiSelectComponent < BaseComponent
    def initialize(name:, options:, selected: [], label: nil, hint: nil, filter_placeholder: "Filter options", all_label: "All sources", none_label: nil, max_chips: 4, **system_arguments)
      super(**system_arguments)
      @name = name
      @options = options
      @selected = Array(selected).map(&:to_s)
      @label = label
      @hint = hint
      @filter_placeholder = filter_placeholder
      @all_label = all_label
      @none_label = none_label.presence || default_none_label
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

    def trigger_label
      return @none_label if @selected.empty?
      return @all_label if @selected.length == @options.length

      selected_options.first&.first.to_s
    end

    def secondary_label
      selected_count = @selected.length
      return nil if selected_count <= 1
      return nil if selected_count == @options.length

      "+#{selected_count - 1}"
    end

    def count_label
      selected_count = @selected.length
      return @none_label if selected_count.zero?
      return @all_label if selected_count == @options.length

      "#{selected_count} selected"
    end

    def none_label
      @none_label
    end

    private

    def default_none_label
      prefix = "All "
      return "No #{@all_label.delete_prefix(prefix)}" if @all_label.start_with?(prefix)

      "None selected"
    end
  end
end
