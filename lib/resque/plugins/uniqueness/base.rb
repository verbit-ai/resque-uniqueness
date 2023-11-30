# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      class LockingError < StandardError; end
      class RedisMultiError < StandardError; end

      # Base class for Lock instance
      class Base
        REDIS_KEY_PREFIX = 'resque_uniqueness'
        REDIS_LOCK_RETRIES = 5

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
          retry_count = 0
          begin
            lock_for(seconds_to_expire)
          rescue RedisMultiError
            # If redis.multi failed to execute all calls, then we should retry
            # it's not clear is it related to redis or redis-client gem or network issue
            # quick tests showed only 1 retry
            retry_count += 1
            log("set_lock redis calls failed, #{retry_count} retry of #{REDIS_LOCK_RETRIES}")
            retry if retry_count <= REDIS_LOCK_RETRIES
          end
        end

        # Locks the job for a specified duration in Redis.
        #
        # @param seconds_to_expire [Integer] The duration for which the lock should be held.
        # @return [String, nil] The result of prev lock, or nil if the worker was not scheduled before.
        # @raise [RedisMultiError] Raised if the multi "transaction" does not succeed.
        def lock_for(seconds_to_expire)
          result = redis.multi { |multi|
            multi.getset(redis_key, job.to_encoded_item_with_queue)
            multi.expire(redis_key, seconds_to_expire)
            remember_lock(multi)
          }
          raise RedisMultiError if result.count < 3

          result.first
        end

        def remove_lock
          redis.multi do |multi|
            multi.del(redis_key)
            forget_lock(multi)
          end
        end

        def remember_lock(redis_client = redis)
          redis_client.sadd(self.class.locks_storage_redis_key, redis_key)
        end

        def forget_lock(redis_client = redis)
          redis_client.srem(self.class.locks_storage_redis_key, redis_key)
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
