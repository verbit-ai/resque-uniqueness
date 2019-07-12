# frozen_string_literal: true

module ResqueSchedulerUniqueJobs
  module Lock
    # While executing lock
    class WhileExecuting < Base
      def locked_on_execute?
        should_lock_on_execute? && already_executing?
      end

      def should_lock_on_execute?
        plugin_activated?
      end

      def lock_execute
        raise LockingError, 'Job is already locked on execute' if locked_on_execute?

        redis.incr(redis_key)
      end

      def unlock_execute
        raise UnlockingError, 'Job is not locked on execute' unless locked_on_execute?

        redis.decr(redis_key)
      end

      private

      def already_executing?
        redis.get(redis_key).to_i.positive?
      end

      def redis_key
        @redis_key ||= "#{EXECUTING_REDIS_KEY_PREFIX}:#{job.redis_key}"
      end
    end
  end
end
