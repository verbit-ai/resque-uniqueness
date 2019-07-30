# frozen_string_literal: true

module Resque
  module Uniqueness
    module Lock
      # Locks from when the client schedule or pushes the job to the queue. Will be unlocked before the server starts processing the job.
      # All other same jobs will be ignored, when trying to queued on schedule with lock.
      # Initialize example:
      #   class TestWorker
      #     @lock_type = :until_executing
      #   end
      class UntilExecuting < Base
        PREFIX = 'scheduled'

        def locked_on_schedule?
          should_lock_on_schedule? && already_scheduled?
        end

        private

        def should_lock_on_schedule?
          true
        end

        def lock_schedule
          raise LockingError, 'Job is already locked on schedule' if locked_on_schedule?

          redis.incr(redis_key)
        end

        def unlock_schedule
          redis.del(redis_key)
        end

        def already_scheduled?
          redis.get(redis_key).to_i.positive?
        end
      end
    end
  end
end
