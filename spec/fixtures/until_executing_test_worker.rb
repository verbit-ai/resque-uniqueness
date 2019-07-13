# frozen_string_literal: true

# A simply until executing test worker
class UntilExecutingTestWorker
  include Resque::Plugins::SchedulerUniqueJob

  @queue = :test_job
  @lock = :until_executing

  def self.perform(*args)
    puts "Starting processing #{worker_attributes(args)}"
    sleep 2
    puts "Ending processing #{worker_attributes(args)}"
  end

  def self.worker_attributes(args)
    "#{self} with args: #{args.to_json}"
  end
end
