# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Locks from when the client schedule or pushes the job to the queue. Will be unlocked before the server starts processing the job.
      # All other same jobs will be ignored, when trying to queued on schedule with lock.
      # Initialize example:
      #   class TestWorker
      #     @lock_type = :until_executing
      #   end
      class UntilExecuting < Base
        PREFIX = 'queueing'

        def queueing_locked?
          should_lock_on_queueing? && already_queueing?
        end

        private

        def should_lock_on_queueing?
          true
        end

        def lock_queueing
          value_before = redis.getset(redis_key, 1)

          # If value before is postive, than lock already present
          raise LockingError, 'Job is already locked on queueing' if value_before.to_i.positive?
        end

        def unlock_queueing
          redis.del(redis_key)
        end

        def already_queueing?
          redis.get(redis_key).to_i.positive?
        end
      end
    end
  end
end
