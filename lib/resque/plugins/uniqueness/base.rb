# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      class LockingError < StandardError; end

      # Base class for Lock instance
      class Base
        REDIS_KEY_PREFIX = 'resque_uniqueness'

        class << self
          # Key to store active locks
          def locks_storage_redis_key
            return unless defined? self::PREFIX

            @locks_storage_redis_key ||= [
              REDIS_KEY_PREFIX,
              self::PREFIX,
              'all_locks'
            ].join(':')
          end
        end

        def initialize(job)
          @job = job
        end

        def redis
          job.redis
        end

        def queueing_locked?
          false
        end

        def perform_locked?
          false
        end

        def try_lock_perform
          lock_perform if should_lock_on_perform?
        end

        def try_lock_queueing(seconds_to_enqueue = 0)
          lock_queueing(seconds_to_enqueue) if should_lock_on_queueing?
        end

        def ensure_unlock_perform
          unlock_perform if perform_locked?
        end

        def ensure_unlock_queueing
          unlock_queueing if queueing_locked?
        end

        def safe_try_lock_queueing
          try_lock_queueing
        rescue LockingError
          nil
        end

        def safe_try_lock_perform
          try_lock_perform
        rescue LockingError
          nil
        end

        def redis_key
          @redis_key ||= [
            self.class::PREFIX,
            REDIS_KEY_PREFIX,
            job.to_uniquness_item
          ].join(':')
        end

        private

        attr_reader :job

        def should_lock_on_queueing?
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

        def lock_queueing(_)
          raise NotImplementedError
        end

        def unlock_queueing
          raise NotImplementedError
        end

        def set_lock(seconds_to_expire) # rubocop:disable Naming/AccessorMethodName
          value_before, = redis.multi {
            redis.getset(redis_key, job.to_encoded_item_with_queue)
            redis.expire(redis_key, seconds_to_expire)
            remember_lock
          }
          value_before
        end

        def remove_lock
          redis.multi do
            redis.del(redis_key)
            forget_lock
          end
        end

        def remember_lock
          redis.sadd(self.class.locks_storage_redis_key, redis_key)
        end

        def forget_lock
          redis.srem(self.class.locks_storage_redis_key, redis_key)
        end

        def lock_present?
          redis.exists?(redis_key)
        end

        def log(message)
          Resque.logger.info("#{message} for key: #{redis_key}")
        end
      end
    end
  end
end
