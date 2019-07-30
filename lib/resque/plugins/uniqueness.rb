# frozen_string_literal: true

module Resque
  module Plugins
    # Resque plugin to make job uniq. Usage:
    #
    #   class YourJobClass
    #     include Resque::Plugins::Uniqueness
    #     # optional:
    #     @lock_type = .....
    # See README for details on settings and lock types.
    module Uniqueness
      def self.included(base)
        base.extend ClassMethods
      end

      # Helper methods and callbacks for jobs
      module ClassMethods
        # Callback which skip enqueue when job locked (returns false, resque skip enqueue step, when any from callbacks will return false)
        def before_enqueue_check_lock_availability(*args)
          Resque.inline? || call_from_scheduler? || job_available_for_schedule?(args)
        end

        # Callback which skip schedule when job is locked on schedule
        def before_schedule_check_lock_availability(*args)
          Resque.inline? || job_available_for_schedule?(args)
        end

        # Callback which lock job on schedule if this job should be locked
        def after_schedule_lock_schedule_if_needed(*args)
          return true if Resque.inline?

          job = create_job(args)
          job.uniqueness.try_lock_schedule
        end

        # Simply returns lock type of current job. If instance_variable `@lock_type` is not set, set it to default value
        def lock_type
          @lock_type ||= Resque::Uniqueness.default_lock_type
          unless Resque::Uniqueness::LOCKS.key?(@lock_type)
            raise NameError, "Unexpected lock type. Available lock types: #{Resque::Uniqueness::LOCKS.keys}, current lock type: #{@lock_type}"
          end

          @lock_type
        end

        # Simple hack.
        # We don't need to skip enqueue step for jobs, which runned from scheduler.
        # Base flow for scheduled jobs:
        #   Resque.enqueue_at -> Resque.enqueue_to (this step could be missed) -> Resque::Job.create -> Resque::Job#perform
        # When we have an `until_executing` lock, and tryig to enqueue or create new same job, we just ignore this job.
        # And in result we ignore jobs which are already locked and should be processed.
        # We can't schedule two same jobs with `until_executing` lock.
        # That's why we sure, that all jobs, which comes from scheduler, should be processed.
        def call_from_scheduler?
          caller.grep(%r{lib/resque/scheduler\.rb.*enqueue}).any?
        end

        private

        def job_available_for_schedule?(args)
          !create_job(args).uniqueness.locked_on_schedule?
        end

        def create_job(args)
          Resque::Job.new(nil, 'class' => name, 'args' => args)
        end
      end
    end
  end
end
