# frozen_string_literal: true

# Simple test worker
class TestWorker
  include Resque::Plugins::SchedulerUniqueJob

  REDIS_KEY = 'specs_output'

  @queue = :test_job

  def self.perform(*args)
    print_to_redis "Starting processing #{worker_attributes(args)}"
    print_to_redis "Ending processing #{worker_attributes(args)}"
  end

  def self.worker_attributes(args)
    "#{self} with args: #{args.to_json}"
  end

  def self.print_to_redis(text)
    old_text = Resque.redis.get(REDIS_KEY) || ''
    Resque.redis.set(REDIS_KEY, old_text + text)
  end
end
