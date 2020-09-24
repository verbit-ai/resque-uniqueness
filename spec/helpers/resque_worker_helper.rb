# frozen_string_literal: true

# Some methods to work with Resque::Worker
module ResqueWorkerHelper
  def worker_processing_jobs
    Resque::Worker.working.map(&:job).map { |job|
      job.transform_keys(&:to_sym)
         .then { |payload:, **item| {**item, payload: payload.transform_keys(&:to_sym)} }
    }
  end
end
