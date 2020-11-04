# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Extension for Resque::Worker class
      # Override working_on method to be sure, that after it job will be removed from
      # the recovering queue
      module WorkerExtension
        def working_on(job)
          return super(job) unless RecoveringQueue.in_allowed_queues?(job.queue)

          Resque.redis.multi do
            super(job)
            RecoveringQueue.remove(job.queue, job.payload)
          end
        end
      end
    end
  end
end
