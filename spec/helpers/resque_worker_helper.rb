# frozen_string_literal: true

# Some methods to work with Resque::Worker
module ResqueWorkerHelper
  def worker_processing_jobs
    Resque::Worker.working.map(&:job).map { |job|
      job.transform_keys(&:to_sym)
         .then { |item| item.merge(payload: item[:payload].transform_keys(&:to_sym)) }
    }
  end
end
