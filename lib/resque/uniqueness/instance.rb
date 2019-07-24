# frozen_string_literal: true

module Resque
  module Uniqueness
    # Uniqueness instance for Resque::Job
    # Implements four locks types:
    #   until_executing - not allow to add into schedule or queue the same jobs with the same args
    #   while_executing - executes the same jobs with the same args one by one
    #   until_and_while_executing - mix of until_executing and while_executing lock types
    #   base - uses for cases, when plugin not included. Just a stub
    class Instance
      extend Forwardable

      LOCKS = {
        until_executing: Lock::UntilExecuting,
        while_executing: Lock::WhileExecuting,
        until_and_while_executing: Lock::UntilAndWhileExecuting,
        none: Lock::None
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

      # Resque uses `Resque.pop(queue)` for retrieving jobs from queue,
      # but in case when we have while_executing lock we should to wait when the same job will finish,
      # before we pop the new same job.
      # That's why we should to find the first appropriate job and remove it from queue.
      def self.pop_unlocked_on_execute_from_queue(queue)
        payload = Resque.data_store.everything_in_queue(queue).find(&method(:unlocked_on_execute?))

        job = payload && Job.new(queue, Resque.decode(payload))
        job&.remove_from_queue
        job
      end

      def self.unlocked_on_execute?(item)
        !Job.new(nil, Resque.decode(item)).locked_on_execute?
      end

      def self.destroy(queue, klass, *args)
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
      def self.remove_queue(queue)
        Resque.data_store.everything_in_queue(queue).uniq.each do |string|
          json = Resque.decode(string)

          unlock_schedule(queue, json)
        end
      end

      def self.unlock_schedule(queue, item)
        job = Job.new(queue, item)
        job.unlock_schedule if job.locked_on_schedule?
      end

      #### Instance methods

      def initialize(job)
        @job = job
        lock_key = payload_class.respond_to?(:lock_type) ? payload_class.lock_type : :none
        @lock = LOCKS[lock_key].new(self)
      end

      def redis_key
        @redis_key ||= "#{REDIS_KEY_PREFIX}:#{encoded_payload}"
      end

      def remove_from_queue
        redis.lrem(queue_key, 1, encoded_payload)
      end

      private

      # Key from lib/resque/data_store.rb `#redis_key_from_queue` method
      # If in further versions of resque key for queue will change - we should to change this method as well
      def queue_key
        "queue:#{queue}"
      end

      def encoded_payload
        @encoded_payload ||= Resque.encode(payload)
      end
    end
  end
end
