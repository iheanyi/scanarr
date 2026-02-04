module UI
  class BaseComponent < ViewComponent::Base
    def initialize(**system_arguments)
      @system_arguments = system_arguments
      super()
    end

    private

    attr_reader :system_arguments

    def merge_classes(*classes)
      classes.flatten.compact.reject(&:empty?).join(" ")
    end

    def cn(*classes)
      merge_classes(*classes)
    end
  end
end
