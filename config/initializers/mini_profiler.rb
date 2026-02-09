# frozen_string_literal: true

if defined?(Rack::MiniProfiler)
  # Store results in tmp/ so they persist across requests and are easier to inspect
  Rack::MiniProfiler.config.storage = Rack::MiniProfiler::FileStore
  Rack::MiniProfiler.config.storage_options = { path: Rails.root.join("tmp/miniprofiler").to_s }

  # Show SQL queries with backtraces in the profiler popup
  Rack::MiniProfiler.config.backtrace_includes = [ /^app/ ]

  # Enable flamegraph support (requires stackprof gem)
  Rack::MiniProfiler.config.enable_advanced_debugging_tools = true

  # Don't auto-start profiling on every request — opt in with ?pp=enable
  # This eliminates the fetch wrapper overhead and console noise
  Rack::MiniProfiler.config.enabled = false
end
