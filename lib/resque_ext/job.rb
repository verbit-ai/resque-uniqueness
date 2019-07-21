# frozen_string_literal: true

module Resque
  # Override resque job class
  class Job
    extend Forwardable

    def_delegators :uniq_wrapper,
                   :lock_execute,
                   :lock_schedule,
                   :unlock_execute,
                   :unlock_schedule,
                   :locked_on_execute?,
                   :locked_on_schedule?,
                   :should_lock_on_execute?,
                   :should_lock_on_schedule?,
                   :remove_from_queue

    class << self
      # Call before Resque put job into queue
      # We should to ignore locking when this method call from scheduler.
      # More information read in the description of `lib.resque_ext/plugin/scheduler_unique_job.rb#call_from_scheduler?` method
      def create_with_uniq(queue, klass, *args)
        if Resque.inline? || klass.call_from_scheduler?
          return create_without_uniq(queue, klass, *args)
        end

        job = new(queue, 'class' => klass, 'args' => decode(encode(args)))

        return if job.locked_on_schedule?

        job.lock_schedule if job.should_lock_on_schedule?
        create_without_uniq(queue, klass, *args)
      end

      alias create_without_uniq create
      alias create create_with_uniq

      # Resque call this method, when starting to process job
      # We should to make sure that we starting to process only unlocked jobs.
      # And also we should to be sure that we unlock_scheduling and lock executing here
      def reserve_with_uniq(queue)
        return reserve_without_uniq(queue) if Resque.inline?

        job = ResqueSchedulerUniqueJobs::Job.pop_unlocked_on_execute_from_queue(queue)

        return unless job

        job.unlock_schedule if job.locked_on_schedule?
        job.lock_execute if job.should_lock_on_execute?
        job
      end

      alias reserve_without_uniq reserve
      alias reserve reserve_with_uniq

      # Destroy with jobs their scheduled locks
      def destroy_with_uniq(queue, klass, *args)
        return destroy_without_uniq(queue, klass, *args) if Resque.inline?

        res = false
        Resque.redis.multi do
          res = destroy_without_uniq(queue, klass, *args)
          ResqueSchedulerUniqueJobs::Job.destroy(queue, klass, *args)
        end
        res
      end

      alias destroy_without_uniq destroy
      alias destroy destroy_with_uniq
    end

    # Main process method in resque
    # On the end of this method we should to unlock executing
    def perform_with_uniq
      perform_without_uniq
    ensure
      unlock_execute if !Resque.inline? && locked_on_execute?
    end

    alias perform_without_uniq perform
    alias perform perform_with_uniq

    def uniq_wrapper
      @uniq_wrapper ||= ResqueSchedulerUniqueJobs::Job.new(self)
    end
  end
end
