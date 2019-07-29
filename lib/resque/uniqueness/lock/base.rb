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
            cursor, keys = Resque.redis.scan(cursor, match: "#{WhileExecuting::PREFIX}:#{REDIS_KEY_PREFIX}:*")
            Resque.redis.del(*keys) if keys.any?
            break if cursor.to_i.zero?
          end
        end

        def initialize(job)
          @job = job
        end

        def redis
          job.redis
        end

        def locked_on_schedule?
          false
        end

        def perform_locked?
          false
        end

        def should_lock_on_schedule?
          false
        end

        def should_lock_on_perform?
          false
        end

        def lock_perform
          raise NotImplementedError
        end

        def unlock_perform
          raise NotImplementedError
        end

        def lock_schedule
          raise NotImplementedError
        end

        def unlock_schedule
          raise NotImplementedError
        end

        private

        attr_reader :job

        def redis_key
          "#{self.class::PREFIX}:#{REDIS_KEY_PREFIX}:#{Resque.encode(job.payload)}"
        end
      end
    end
  end
end
