# frozen_string_literal: true

require 'resque'
require 'resque-scheduler'
require_relative 'uniqueness/version'
require_relative 'uniqueness/lock/base'
require_relative 'uniqueness/lock/none'
require_relative 'uniqueness/lock/while_executing'
require_relative 'uniqueness/lock/until_executing'
require_relative 'uniqueness/lock/until_and_while_executing'
require_relative 'uniqueness/instance'
require_relative 'uniqueness/job_extension'
require_relative 'uniqueness/resque_extension'
require_relative 'plugins/uniqueness'

Resque.redis = 'localhost:6379/resque_uniqueness_test' if ENV['REDIS_ENV'] == 'test'

Resque.prepend Resque::Uniqueness::ResqueExtension
Resque::Job.prepend Resque::Uniqueness::JobExtension

module Resque
  # Base gem module
  module Uniqueness
    REDIS_KEY_PREFIX = 'resque_uniqueness'
    EXECUTING_REDIS_KEY_PREFIX = 'executing'
    SCHEDULED_REDIS_KEY_PREFIX = 'scheduled'

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
        job&.uniqueness&.remove_from_queue
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
    end

    # Clear all executing locks from redis (could be present because of unexpected terminated)
    Lock::Base.clear_executing
  end
end
