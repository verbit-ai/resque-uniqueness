# frozen_string_literal: true

module Resque
  class << self
    def remove_queue_with_uniq(queue)
      res = remove_queue_without_uniq(queue)
      ResqueSchedulerUniqueJobs::Job.remove_queue(queue)
      res
    end

    alias remove_queue_without_uniq remove_queue
    alias remove_queue remove_queue_with_uniq

    def remove_delayed_job_with_uniq(encoded_item)
      res = remove_delayed_job_without_uniq(encoded_item)
      ResqueSchedulerUniqueJobs::Job.unlock_schedule(nil, decode(encoded_item))
      res
    end

    alias remove_delayed_job_without_uniq remove_delayed_job
    alias remove_delayed_job remove_delayed_job_with_uniq

    def remove_delayed_job_from_timestamp_with_uniq(timestamp, klass, *args)
      removed_count = remove_delayed_job_from_timestamp_without_uniq(timestamp, klass, *args)
      return removed_count unless removed_count.positive?

      ResqueSchedulerUniqueJobs::Job.unlock_schedule(nil, 'class' => klass.to_s, 'args' => args)
      removed_count
    end

    alias remove_delayed_job_from_timestamp_without_uniq remove_delayed_job_from_timestamp
    alias remove_delayed_job_from_timestamp remove_delayed_job_from_timestamp_with_uniq
  end
end
