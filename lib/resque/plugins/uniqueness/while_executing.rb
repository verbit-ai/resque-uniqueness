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
        # We should to expiring while_executing lock to prevent unexpected terminated
        LOCK_EXPIRE_SECONDS = 60
        LOCK_RENEWAL_WAIT_SECONDS = 5

        def perform_locked?
          should_lock_on_perform? && lock_present?
        end

        private

        def should_lock_on_perform?
          true
        end

        def lock_perform
          value_before = set_lock(LOCK_EXPIRE_SECONDS)
          log('Performing locked')

          # If value before is postive, than lock already present
          if value_before
            log('Performing locking error')
            raise LockingError, 'Job is already locked on perform'
          end

          run_lock_renewal
        end

        def unlock_perform
          remove_lock
          log('Performing unlocked')
        end

        # When server was unexpected terminated all our locks will still be enabled on the redis.
        # We can't just remove every performing lock on app initializing, because  multiple server
        # instances could work with one redis server.
        def run_lock_renewal
          Thread.new do
            while lock_present?
              redis.expire(redis_key, LOCK_EXPIRE_SECONDS)
              sleep LOCK_RENEWAL_WAIT_SECONDS
            end
          end
        end
      end
    end
  end
end
