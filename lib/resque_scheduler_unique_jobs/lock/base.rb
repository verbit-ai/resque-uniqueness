# frozen_string_literal: true

module ResqueSchedulerUniqueJobs
  module Lock
    class LockingError < StandardError; end
    class UnlockingError < StandardError; end

    # Base class for Lock instance
    class Base
      def self.clear_executing
        cursor = '0'
        loop do
          cursor, keys = Resque.redis.scan(cursor, match: "#{EXECUTING_REDIS_KEY_PREFIX}:#{REDIS_KEY_PREFIX}:*")
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

      attr_reader :job

      def plugin_activated?
        job.payload_class.included_modules.include?(::Resque::Plugins::SchedulerUniqueJob)
      end
    end
  end
end
