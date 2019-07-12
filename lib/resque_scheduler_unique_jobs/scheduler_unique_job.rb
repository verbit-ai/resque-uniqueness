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
        def self.extended(base)
          @klass = base
        end

        def before_enqueue_check_lock_availability(*args)
          job_available_for_schedule?(args)
        end

        def before_schedule_check_lock_availability(*args)
          job_available_for_schedule?(args)
        end

        def lock
          @lock ||= :until_executing
        end

        private

        def job_available_for_schedule?(args)
          !Resque::Job.new(nil, 'class' => name, 'args' => args).locked_on_schedule?
        end
      end
    end
  end
end
