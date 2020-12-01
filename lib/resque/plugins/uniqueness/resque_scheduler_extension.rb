# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Extension for Resque Scheduler
      # We prepend it to resque module and override `delayed_push` and `enqueue_at_with_queue`
      # methods from `Resque::Scheduler::DelayingExtensions`
      # for allowing locks to work in multithreading.
      module ResqueSchedulerExtension
        def self.prepended(base)
          class << base
            prepend ClassMethods
          end
        end

        # Class methods for overriding ResqueScheduler behavior
        module ClassMethods
          # Override Resque::Scheduler::DelayingExtensions.enqueue_at_with_queue method
          # See more info in comments for
          # `Resque::Plugins::Uniqueness::ResqueSchedulerExtension.delayed_push` method
          def enqueue_at_with_queue(queue, timestamp, klass, *args)
            super
            # Exception could be raised in
            # `Resque::Plugins::Uniqueness::ResqueSchedulerExtension.delayed_push`
          rescue LockingError
            false
          end

          # Override Resque::Scheduler::DelayingExtensions.delayed_push
          # We couldn't lock job in the after hook, because of multithreading app can take same jobs
          # at the same time, and only on locking one from them will raise exception.
          # But it will be after the thread will put job to the schedule.
          #
          # We couldn't lock job in the before hook as well, because of next hooks can return false
          # and the job will have lock, but not been scheduled.
          def delayed_push(timestamp, item)
            # This line could raise `LockingError` and it should be handled in the
            # `enqueue_at_with_queue` method
            #
            # We can't handle exception here, because of jobs, which raise an error on locking
            # will run after hooks, but its unexpected behavior.
            Resque::Job.new(item[:queue], 'class' => item[:class], 'args' => item[:args])
                       .uniqueness
                       .try_lock_queueing(timestamp.to_i - Time.now.to_i)
            super
          end
        end
      end
    end
  end
end
