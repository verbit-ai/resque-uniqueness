# frozen_string_literal: true

module Resque
  module Plugins
    # Resque plugin for enable unique jobs
    module SchedulerUniqueJob
      def self.included(base)
        base.extend ClassMethods
      end

      # Class methods
      module ClassMethods
        def before_enqueue_check_lock_availability(*args)
          call_from_scheduler? || job_available_for_schedule?(args)
        end

        def before_schedule_check_lock_availability(*args)
          job_available_for_schedule?(args)
        end

        def after_schedule_lock_schedule_if_needed(*args)
          job = create_job(args)
          job.lock_schedule if job.should_lock_on_schedule?
        end

        def lock
          @lock ||= :until_executing
        end

        def call_from_scheduler?
          !caller.grep(%r{lib\/resque\/scheduler\.rb.*enqueue}).empty?
        end

        private

        def job_available_for_schedule?(args)
          !create_job(args).locked_on_schedule?
        end

        def create_job(args)
          Resque::Job.new(nil, 'class' => name, 'args' => args)
        end
      end
    end
  end
end
