# frozen_string_literal: true

module ResqueSchedulerUniqueJobs
  module Lock
    # Locks from when the client schedule or pushes the job to the queue. Will be unlocked before the server starts processing the job.
    # All other same jobs will be ignored, when trying to queued ot schedule with lock.
    # Initialize example:
    #   class TestWorker
    #     @lock = :until_executing
    #   end
    class UntilExecuting < Base
      def locked_on_schedule?
        should_lock_on_schedule? && already_scheduled?
      end

      def should_lock_on_schedule?
        plugin_activated?
      end

      def lock_schedule
        raise LockingError, 'Job is already locked on schedule' if locked_on_schedule?

        redis.incr(redis_key)
      end

      def unlock_schedule
        raise UnlockingError, 'Job is not locked on schedule' unless locked_on_schedule?

        redis.del(redis_key)
      end

      private

      def already_scheduled?
        redis.get(redis_key).to_i.positive?
      end

      def redis_key
        @redis_key ||= "#{SCHEDULED_REDIS_KEY_PREFIX}:#{job.redis_key}"
      end
    end
  end
end
