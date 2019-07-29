# frozen_string_literal: true

module Resque
  module Uniqueness
    module Lock
      class LockingError < StandardError; end
      class UnlockingError < StandardError; end

      # Base class for Lock instance
      class Base
        # Remove all executing keys from redis.
        # Using to fix unexpected terminated problem.
        def self.clear_executing
          cursor = '0'
          loop do
            cursor, keys = Resque.redis.scan(cursor, match: "#{EXECUTING_REDIS_KEY_PREFIX}:#{REDIS_KEY_PREFIX}:*")
            Resque.redis.del(*keys) if keys.any?
            break if cursor.to_i.zero?
          end
        end

        def initialize(uniqueness_instance)
          @uniqueness_instance = uniqueness_instance
        end

        def redis
          uniqueness_instance.redis
        end

        def locked_on_schedule?
          false
        end

        def locked_on_execute?
          false
        end

        def should_lock_on_schedule?
          false
        end

        def should_lock_on_execute?
          false
        end

        def lock_execute
          raise NotImplementedError
        end

        def unlock_execute
          raise NotImplementedError
        end

        def lock_schedule
          raise NotImplementedError
        end

        def unlock_schedule
          raise NotImplementedError
        end

        private

        attr_reader :uniqueness_instance
      end
    end
  end
end
