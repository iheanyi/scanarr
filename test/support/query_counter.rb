# frozen_string_literal: true

# Counts SQL queries executed within a block.
# Excludes SCHEMA, CACHE, and transaction management queries.
#
# Usage:
#   count = count_queries { SomeModel.all.to_a }
#   assert count <= 3, "Expected at most 3 queries, got #{count}"
#
module QueryCounter
  IGNORED_PATTERNS = /\A(SCHEMA|CACHE|SAVEPOINT|RELEASE SAVEPOINT|BEGIN|COMMIT|ROLLBACK|SET)/i

  def count_queries(&block)
    counter = 0
    callback = lambda { |_name, _start, _finish, _id, payload|
      next if payload[:name]&.match?(IGNORED_PATTERNS)
      next if payload[:sql]&.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/i)
      counter += 1
    }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    counter
  end

  def assert_query_count(expected, message = nil, &block)
    actual = count_queries(&block)
    msg = message || "Expected #{expected} queries, but got #{actual}"

    assert_equal expected, actual, msg
  end

  def assert_queries_at_most(max, message = nil, &block)
    actual = count_queries(&block)
    msg = message || "Expected at most #{max} queries, but got #{actual}"

    assert_operator actual, :<=, max, msg
  end
end
