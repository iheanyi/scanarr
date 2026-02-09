ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Opt-in runtime YJIT enablement. Safe on Rubies without YJIT support.
if ENV["ENABLE_YJIT"] == "1" && defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable)
  RubyVM::YJIT.enable unless RubyVM::YJIT.enabled?
end

require "bootsnap/setup" # Speed up boot time by caching expensive operations.
