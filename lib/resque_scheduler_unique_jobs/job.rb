# frozen_string_literal: true

module ResqueSchedulerUniqueJobs
  # Container for ResqueSchedulerUniqueJobs Job representation
  class Job
    extend Forwardable

    LOCKS = {
      while_executing: ResqueSchedulerUniqueJobs::Lock::WhileExecuting
    }.freeze

    attr_reader :job

    def_delegators :@job,
                   :redis,
                   :payload,
                   :queue,
                   :payload_class

    def_delegators :@lock,
                   :lock_execute,
                   :lock_schedule,
                   :unlock_execute,
                   :unlock_schedule,
                   :locked_on_execute?,
                   :locked_on_schedule?,
                   :should_lock_on_execute?,
                   :should_lock_on_schedule?

    #### Class methods

    def self.pop_unlocked_on_execute_from_queue(queue)
      payload = Resque.data_store.everything_in_queue(queue).find(&method(:unlocked_on_execute?))

      job = payload && Resque::Job.new(queue, Resque.decode(payload))
      job&.remove_from_queue
      job
    end

    def self.unlocked_on_execute?(item)
      !new(Resque::Job.new(nil, Resque.decode(item))).locked_on_execute?
    end

    #### Instance methods

    def initialize(job)
      @job = job
      @lock = LOCKS[payload_class.lock].new(self)
    end

    def redis_key
      @redis_key ||= "#{REDIS_KEY_PREFIX}:#{encoded_payload}"
    end

    def remove_from_queue
      redis.lrem(queue_key, 1, encoded_payload)
    end

    private

    def queue_key
      "queue:#{queue}"
    end

    def encoded_payload
      @encoded_payload ||= Resque.encode(payload)
    end
  end
end
