# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Mix of UntilExecuting and WhileExecuting locks.
      # Locks when the client pushes the job to the queue.
      # The queue will be unlocked when the server starts processing the job.
      # The server then goes on to creating a runtime lock for the job to prevent simultaneous jobs from being executed.
      # As soon as the server starts processing a job, the client can push the same job to the queue.
      #   @lock_type = :until_and_while_executing
      class UntilAndWhileExecuting < Base
        extend Forwardable

        def initialize(job)
          super(job)
          @until_executing_lock = UntilExecuting.new(job)
          @while_executing_lock = WhileExecuting.new(job)
        end

        def_delegators :@until_executing_lock,
                       :queueing_locked?,
                       :try_lock_queueing,
                       :ensure_unlock_queueing

        def_delegators :@while_executing_lock,
                       :perform_locked?,
                       :try_lock_perform,
                       :ensure_unlock_perform
      end
    end
  end
end
