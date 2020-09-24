# frozen_string_literal: true

# Some methods to work with Resque::Job
module JobHelper
  include BaseHelper

  def create_jobs_from(items, queue = self.queue)
    ensure_array(items)
      .map { |item| create_job_from(item, queue) }
  end

  def create_job_from(item, queue = self.queue)
    Resque::Job.new(queue, item.transform_keys(&:to_s))
  end
end
