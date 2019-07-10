# frozen_string_literal: true

module ResqueSchedulerUniqueJobs
  # Container for ResqueSchedulerUniqueJobs Job representation
  class Job
    #### Class methods

    def self.find_uniq_job_in_queue(queue)
      payload = Resque.data_store.everything_in_queue(queue).find(&method(:item_uniq?))

      payload && Resque::Job.new(queue, Resque.decode(payload))
    end

    def self.item_uniq?(item)
      new(Resque::Job.new(nil, Resque.decode(item))).uniq?
    end

    #### Instance methods

    def initialize(job)
      @job = job
    end

    def uniq?
      !executing_lock_enabled? || !already_executing?
    end

    def remove_from_queue
      job.redis.lrem(queue_key, 1, encoded_payload)
    end

    def push_to_executing_pool
      job.redis.incr(executing_redis_key)
    end

    def pop_from_executing_pool
      job.redis.decr(executing_redis_key)
    end

    private

    attr_reader :job

    def queue_key
      "queue:#{job.queue}"
    end

    def already_executing?
      executing_pool_size.positive?
    end

    def executing_pool_size
      Resque.redis.get(executing_redis_key).to_i
    end

    def executing_lock_enabled?
      job.payload_class.included_modules.include?(::Resque::Plugins::SchedulerUniqueJob) &&
        %i[while_executing until_and_while_executing].include?(job.payload_class.lock)
    end

    def processing_redis_key
      @processing_redis_key ||= "processing:#{redis_key}"
    end

    def executing_redis_key
      @executing_redis_key ||= "executing:#{redis_key}"
    end

    def redis_key
      @redis_key ||= "#{REDIS_KEY_PREFIX}:#{encoded_payload}"
    end

    def encoded_payload
      @encoded_payload ||= Resque.encode(job.payload)
    end
  end
end
