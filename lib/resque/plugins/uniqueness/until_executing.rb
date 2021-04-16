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
        EXPIRING_TIME = 172_800 # 2 days in seconds

        def queueing_locked?
          should_lock_on_queueing? && lock_present?
        end

        private

        def should_lock_on_queueing?
          true
        end

        def lock_queueing(seconds_to_enqueue = 0)
          # Expire queueing lock after two days. If lock installing for scheduled job - should
          # add seconds which scheduler should wait before push this job to queue.
          value_before = set_lock(seconds_to_enqueue + EXPIRING_TIME)
          log('Queueing locked')

          # If value before is postive, than lock already present
          return unless value_before

          log('Queueing locking error')
          raise LockingError, 'Job is already locked on queueing'
        end

        def unlock_queueing
          remove_lock
          log('Queueing unlocked')
        end
      end
    end
  end
end
