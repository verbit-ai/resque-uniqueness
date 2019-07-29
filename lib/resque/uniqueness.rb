# frozen_string_literal: true

require 'resque'
require 'resque-scheduler'
require_relative 'uniqueness/version'
require_relative 'uniqueness/lock/base'
require_relative 'uniqueness/lock/none'
require_relative 'uniqueness/lock/while_executing'
require_relative 'uniqueness/lock/until_executing'
require_relative 'uniqueness/lock/until_and_while_executing'
require_relative 'uniqueness/job_extension'
require_relative 'uniqueness/resque_extension'
require_relative 'plugins/uniqueness'

Resque.prepend Resque::Uniqueness::ResqueExtension
Resque::Job.prepend Resque::Uniqueness::JobExtension

module Resque
  # Base gem module
  module Uniqueness
    REDIS_KEY_PREFIX = 'resque_uniqueness'

    LOCKS = {
      until_executing: Lock::UntilExecuting,
      while_executing: Lock::WhileExecuting,
      until_and_while_executing: Lock::UntilAndWhileExecuting,
      none: Lock::None
    }.freeze

    @default_lock_type = :until_executing

    class << self
      attr_accessor :default_lock_type

      # Resque uses `Resque.pop(queue)` for retrieving jobs from queue,
      # but in case when we have while_executing lock we should to wait when the same job will finish,
      # before we pop the new same job.
      # That's why we should to find the first appropriate job and remove it from queue.
      def pop_unlocked_on_execute_from_queue(queue)
        payload = Resque.data_store.everything_in_queue(queue).find(&method(:unlocked_on_execute?))

        job = payload && Resque::Job.new(queue, Resque.decode(payload))
        remove_job_from_queue(queue, job)
        job
      end

      def unlocked_on_execute?(item)
        !Resque::Job.new(nil, Resque.decode(item)).uniqueness.locked_on_execute?
      end

      def destroy(queue, klass, *args)
        klass = klass.to_s
        Resque.data_store.everything_in_queue(queue).each do |string|
          json = Resque.decode(string)
          next unless json['class'] == klass
          # Resque destroys all jobs with the certain class if args is empty.
          # That's why we should to check presence of args before comparing it with the args from redis
          next if args.any? && json['args'] != args

          unlock_schedule(queue, json)
        end
      end

      # Unlock schedule for every job in the certain queue
      def remove_queue(queue)
        Resque.data_store.everything_in_queue(queue).uniq.each do |string|
          json = Resque.decode(string)

          unlock_schedule(queue, json)
        end
      end

      def unlock_schedule(queue, item)
        job = Resque::Job.new(queue, item)
        job.uniqueness.unlock_schedule if job.uniqueness.locked_on_schedule?
      end

      def fetch_for(job)
        lock_key = job.payload_class.respond_to?(:lock_type) ? job.payload_class.lock_type : :none
        LOCKS[lock_key].new(job)
      end

      private

      def remove_job_from_queue(queue, job)
        return false unless job

        job.redis.lrem(queue_key(queue), 1, Resque.encode(job.payload))
      end

      # Key from lib/resque/data_store.rb `#redis_key_from_queue` method
      # If in further versions of resque key for queue will change - we should to change this method as well
      def queue_key(queue)
        "queue:#{queue}"
      end
    end
  end
end

# Clear all executing locks from redis (could be present because of unexpected terminated)
Resque::Uniqueness::Lock::Base.clear_executing
