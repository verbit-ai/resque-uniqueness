# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Create a lock when the job starting to processing with server.
      # Removes lock after tje job will finish.
      # All other same jobs will starts after the lock will be realised.
      # Job will be executed one by one.
      # Initialize example:
      #   class TestWorker
      #     @lock_type = :while_executing
      #   end
      class WhileExecuting < Base
        PREFIX = 'performing'

        def perform_locked?
          should_lock_on_perform? && already_performing?
        end

        private

        def should_lock_on_perform?
          true
        end

        def lock_perform
          value_before = redis.getset(redis_key, 1)

          # If value before is postive, than lock already present
          raise LockingError, 'Job is already locked on perform' if value_before.to_i.positive?
        end

        def unlock_perform
          redis.del(redis_key)
        end

        def already_performing?
          redis.get(redis_key).to_i.positive?
        end
      end
    end
  end
end
