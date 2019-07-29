# frozen_string_literal: true

module Resque
  module Uniqueness
    module Lock
      # Create a lock when the job starting to processing with server.
      # Removes lock after tje job will finish.
      # All other same jobs will starts after the lock will be realised.
      # Job will be executed one by one.
      # Initialize example:
      #   class TestWorker
      #     @lock_type = :while_executing
      #   end
      class WhileExecuting < Base
        PREFIX = 'executing'

        def perform_locked?
          should_lock_on_perform? && already_executing?
        end

        def should_lock_on_perform?
          true
        end

        def lock_perform
          raise LockingError, 'Job is already locked on execute' if perform_locked?

          redis.incr(redis_key)
        end

        def unlock_perform
          raise UnlockingError, 'Job is not locked on execute' unless perform_locked?

          redis.del(redis_key)
        end

        private

        def already_executing?
          redis.get(redis_key).to_i.positive?
        end
      end
    end
  end
end
