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
