# frozen_string_literal: true

module ResqueSchedulerUniqueJobs
  module Lock
    # Mix of UntilExecuting and WhileExecuting locks.
    # Locks when the client pushes the job to the queue.
    # The queue will be unlocked when the server starts processing the job.
    # The server then goes on to creating a runtime lock for the job to prevent simultaneous jobs from being executed.
    # As soon as the server starts processing a job, the client can push the same job to the queue.
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
