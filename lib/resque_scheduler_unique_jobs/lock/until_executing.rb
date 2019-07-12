# frozen_string_literal: true

module ResqueSchedulerUniqueJobs
  module Lock
    # Until executing lock
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

        redis.decr(redis_key)
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
