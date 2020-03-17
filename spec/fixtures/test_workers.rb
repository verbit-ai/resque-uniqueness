# frozen_string_literal: true

require 'securerandom'
# Simple test worker
class TestWorker
  include Resque::Plugins::Uniqueness

  REDIS_KEY = 'specs_output'

  @queue = :test_job

  def self.perform(*args)
    before_processing(args)
    sleep 1
    yield if block_given?
  ensure
    after_processing(args)
  end

  def self.print_to_redis(text)
    old_text = Resque.redis.get(REDIS_KEY) || ''
    Resque.redis.set(REDIS_KEY, old_text + text)
    puts text
  end

  def self.before_processing(args)
    Resque.redis.set("test_worker_performing:#{key}", 'test')
    print_to_redis "Starting processing #{worker_attributes(args)}"
  end

  def self.after_processing(args)
    print_to_redis "Ending processing #{worker_attributes(args)}"
    Resque.redis.del("test_worker_performing:#{key}")
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
