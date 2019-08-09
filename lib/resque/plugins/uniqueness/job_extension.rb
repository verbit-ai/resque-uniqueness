# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Extension for Resque::Job class
      # Override create, reserve, destroy and perform methods for allowing to work with lock
      # And adding uniqueness wrapper to the Resque::Job
      module JobExtension
        def self.prepended(base)
          class << base
            prepend ClassMethods
          end
        end

        # Class methods for overriding basic Resque::Job class
        module ClassMethods
          # Call before Resque put job into queue
          # We should to ignore locking when this method call from scheduler.
          # More information read in the description of `lib.resque_ext/plugin/scheduler_unique_job.rb#call_from_scheduler?` method
          def create(queue, klass, *args)
            return super if Resque.inline? || klass.call_from_scheduler?

            job = new(queue, 'class' => klass.to_s, 'args' => decode(encode(args)))

            return if job.uniqueness.queueing_locked?

            job.uniqueness.try_lock_queueing
            super
          rescue LockingError => e
            # In case when two threads locking the same job at the same moment -
            # uniqueness will raise this error for one from them.
            # In this case we should to return nil, but if parent method can handle error -
            # we should to throw it to the parent for preventing to run after hooks.
            raise if parent_handle_locking_error?(e)

            nil
          end

          # Resque call this method, when starting to process job
          # We should to make sure that we starting to process only unlocked jobs.
          # And also we should to be sure that we unlock_queueing and lock performing here
          def reserve(queue)
            return super if Resque.inline?

            job = Resque::Plugins::Uniqueness.pop_perform_unlocked(queue)

            return unless job

            job.uniqueness.ensure_unlock_queueing
            job.uniqueness.try_lock_perform
            job
          rescue LockingError
            # In case when two threads pick up the same job, which don't locked yet,
            # one from them will fail with `LockingError`
            # And in this case we should to push job back
            Resque::Plugins::Uniqueness.push(queue, job.payload)
            nil
          end

          # Destroy with jobs their queueing locks
          def destroy(queue, klass, *args)
            super.tap do
              Resque::Plugins::Uniqueness.destroy(queue, klass, *args) unless Resque.inline?
            end
          end
        end

        def uniqueness
          @uniqueness ||= Resque::Plugins::Uniqueness.fetch_for(self)
        end

        # For now only `Resque.enqueue_to` can and should handle LockingError exception.
        # In case when we don't handle it there - we will run after hooks for job,
        # which don't queued
        # We handle this exception in Resque::Plugins::Uniqueness::ResqueExtension.enqueue_to method
        def parent_handle_locking_error?(error)
          error.backtrace.any? { |trace| trace =~ /resque\.rb.*`enqueue_to/ }
        end
      end
    end
  end
end
