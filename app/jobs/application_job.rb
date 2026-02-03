class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Retry on transient database errors
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  retry_on PG::ConnectionBad, wait: 5.seconds, attempts: 3 if defined?(PG::ConnectionBad)
end
