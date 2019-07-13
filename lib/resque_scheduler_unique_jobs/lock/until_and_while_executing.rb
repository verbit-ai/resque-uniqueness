# frozen_string_literal: true

module ResqueSchedulerUniqueJobs
  module Lock
    # Until executing lock
    class UntilAndWhileExecuting < Base
      extend Forwardable

      def initialize(job)
        super(job)
        @until_executing_lock = UntilExecuting.new(job)
        @while_executing_lock = WhileExecuting.new(job)
      end

      def_delegators :@until_executing_lock,
                     :locked_on_schedule?,
                     :should_lock_on_schedule?,
                     :lock_schedule,
                     :unlock_schedule

      def_delegators :@while_executing_lock,
                     :locked_on_execute?,
                     :should_lock_on_execute?,
                     :lock_execute,
                     :unlock_execute
    end
  end
end
