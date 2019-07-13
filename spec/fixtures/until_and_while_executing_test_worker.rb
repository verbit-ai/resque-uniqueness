# frozen_string_literal: true

# A simply until and while executing test worker
class UntilAndWhileExecutingTestWorker
  include Resque::Plugins::SchedulerUniqueJob

  @queue = :test_job
  @lock = :until_and_while_executing

  def self.perform(*args)
    puts "Starting processing #{worker_attributes(args)}"
    sleep 10
    puts "Ending processing #{worker_attributes(args)}"
  end

  def self.worker_attributes(args)
    "#{self} with args: #{args.to_json}"
  end
end
