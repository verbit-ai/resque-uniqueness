# frozen_string_literal: true

module Resque
  module Uniqueness
    # Extension for Resque::Job class
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

          job = new(queue, 'class' => klass, 'args' => decode(encode(args)))

          return if job.uniqueness.locked_on_schedule?

          job.uniqueness.lock_schedule if job.uniqueness.should_lock_on_schedule?
          super
        end

        # Resque call this method, when starting to process job
        # We should to make sure that we starting to process only unlocked jobs.
        # And also we should to be sure that we unlock_scheduling and lock executing here
        def reserve(queue)
          return super if Resque.inline?

          job = Resque::Uniqueness.pop_unlocked_on_execute_from_queue(queue)

          return unless job

          job.uniqueness.unlock_schedule if job.uniqueness.locked_on_schedule?
          job.uniqueness.lock_execute if job.uniqueness.should_lock_on_execute?
          job
        end

        # Destroy with jobs their scheduled locks
        def destroy(queue, klass, *args)
          return super if Resque.inline?

          res = false
          Resque.redis.multi do
            res = super
            Resque::Uniqueness.destroy(queue, klass, *args)
          end
          res
        end
      end

      # Main process method in resque
      # On the end of this method we should to unlock executing
      def perform
        super
      ensure
        uniqueness.unlock_execute if uniqueness.locked_on_execute?
      end

      def uniqueness
        @uniqueness ||= Resque::Uniqueness::Instance.new(self)
      end
    end
  end
end
