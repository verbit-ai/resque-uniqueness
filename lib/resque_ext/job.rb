# frozen_string_literal: true

module Resque
  # Override resque job class
  class Job
    class << self
      def reserve_with_uniq(queue)
        return reserve_without_uniq if Resque.inline?

        job = ResqueSchedulerUniqueJobs::Job.find_uniq_job_in_queue(queue)

        return unless job

        job.uniq_wrapper.push_to_executing_pool
        job.uniq_wrapper.remove_from_queue
        job
      end

      alias reserve_without_uniq reserve
      alias reserve reserve_with_uniq
    end

    def uniq_wrapper
      @uniq_wrapper ||= ResqueSchedulerUniqueJobs::Job.new(self)
    end

    def perform_with_uniq
      perform_without_uniq
    ensure
      uniq_wrapper.pop_from_executing_pool
    end

    alias perform_without_uniq perform
    alias perform perform_with_uniq
  end
end
