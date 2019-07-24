# frozen_string_literal: true

module Resque
  module Uniqueness
    module Lock
      # Mix of UntilExecuting and WhileExecuting locks.
      # Locks when the client pushes the job to the queue.
      # The queue will be unlocked when the server starts processing the job.
      # The server then goes on to creating a runtime lock for the job to prevent simultaneous jobs from being executed.
      # As soon as the server starts processing a job, the client can push the same job to the queue.
      #   @lock_type = :until_and_while_executing
      class UntilAndWhileExecuting < Base
        extend Forwardable

        def initialize(uniqueness_instance)
          super(uniqueness_instance)
          @until_executing_lock = UntilExecuting.new(uniqueness_instance)
          @while_executing_lock = WhileExecuting.new(uniqueness_instance)
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
end
