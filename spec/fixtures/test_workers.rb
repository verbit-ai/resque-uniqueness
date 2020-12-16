# frozen_string_literal: true

require 'resque-retry'

# Simple test worker
class TestWorker
  include Resque::Plugins::Uniqueness

  REDIS_KEY = 'specs_output'

  @queue = :test_job

  def self.perform(*args)
    before_processing(args)
    if block_given?
      yield
    else
      sleep 1
    end
  ensure
    after_processing(args)
  end

  def self.before_perform_track_processing(*)
    Resque.redis.setex("test_worker_performing:#{key}", 10, 'test')
  end

  def self.before_processing(args)
    print_to_redis "Starting processing #{worker_attributes(args)}"
  end

  def self.after_processing(args)
    print_to_redis "Ending processing #{worker_attributes(args)}"
    Resque.redis.del("test_worker_performing:#{key}")
  end

  def self.print_to_redis(text)
    old_text = Resque.redis.get(REDIS_KEY) || ''
    Resque.redis.set(REDIS_KEY, old_text + text)
    Resque.logger.info text
  end

  def self.worker_attributes(args)
    "#{self} with args: #{args.to_json}"
  end

  def self.key
    @key ||= SecureRandom.uuid
  end
end

class WhileExecutingWorker < TestWorker
  @lock_type = :while_executing
  @queue = :test_job
end

class WhileExecutingPerformErrorWorker < TestWorker
  @lock_type = :while_executing
  @queue = :test_job

  def self.perform(*args)
    super do
      raise 'test error'
    end
  end
end

class UntilExecutingWorker < TestWorker
  @lock_type = :until_executing
  @queue = :test_job
end

class UntilAndWhileExecutingWorker < TestWorker
  @lock_type = :until_and_while_executing
  @queue = :test_job

  def self.perform(*args)
    super do
      sleep 4
    end
  end
end

class UntilAndWhileExecutingPerformErrorWorker < TestWorker
  @lock_type = :until_and_while_executing
  @queue = :test_job

  def self.perform(*args)
    super do
      sleep 4
      raise 'test error'
    end
  end
end

class UntilExecutingWithUniqueArgsWorker < TestWorker
  @queue = :test_job
  @lock_type = :until_executing

  def self.unique_args(first, *)
    [first]
  end
end

class NoneWorker < TestWorker
  @lock_type = :none
  @queue = :test_job
end

UUIDS_FINISHED_REDIS_KEY = 'workers:finished:uuids'

class UntilExecutingRecoverWorker < UntilExecutingWorker
  extend Resque::Plugins::Retry

  @retry_limit = 100
  @queue = :test_job_recovering

  retry_criteria_check do |_e, uuid|
    return false if Resque.redis.lrange(UUIDS_FINISHED_REDIS_KEY, 0, -1).include?(uuid)

    false
  end

  def self.perform(uuid)
    Resque.redis.rpush(UUIDS_FINISHED_REDIS_KEY, uuid)
    super { sleep rand(0.1..3) }
  end
end

class JobsExtractorAcceptanceWorker < TestWorker
  @lock_type = :until_executing
  @queue = :test_job

  def self.perform(uuid)
    key = "worker_data:#{uuid}"
    super {
      if Resque.redis.incr(key) < 5
        Resque.enqueue_in(rand(1..5), self, uuid)
      else
        Resque.redis.del(key)
      end
    }
  end
end
