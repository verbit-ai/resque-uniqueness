# frozen_string_literal: true

require 'resque'
require 'resque-scheduler'
require_relative 'uniqueness/version'
require_relative 'uniqueness/base'
require_relative 'uniqueness/none'
require_relative 'uniqueness/while_executing'
require_relative 'uniqueness/until_executing'
require_relative 'uniqueness/until_and_while_executing'
require_relative 'uniqueness/job_extension'
require_relative 'uniqueness/resque_extension'

Resque.prepend Resque::Plugins::Uniqueness::ResqueExtension
Resque::Job.prepend Resque::Plugins::Uniqueness::JobExtension

module Resque
  module Plugins
    # Plugin to ensure Resque job's uniqueness by job class and arguments. It has three modes of uniqueness:
    #   1. until_executing: while the job is in the queue or schedule, no other job of the same class with the same arguments will be pushed to the queue or scheduled (it would be just ignored); when the job is starting to perform, the lock is cleared and another job can be pushed to the queue or scheduled;
    #   2. while_executing: while the job is performing, no other job of the same class with the same argument will start performing (it will wait in the queue until the one performing is finished);
    #   3. until_and_while_executing: a combination of the above: while the job is pending, another one can not be put in the queue or scheduled; and then while it is performing, another can be pushed, but will not be performed until the current one is finished.
    #
    # It is implemented by intercepting (patching) the following places in Resque:
    #   1. ignoring schedule (see {Plugins::Uniqueness.before_schedule_check_lock_availability});
    #   2. lock scheduling (see {Plugins::Uniqueness.after_schedule_lock_schedule_if_needed});
    #   3. ignoring enqueue (see {Plugins::Uniqueness.before_enqueue_check_lock_availability});
    #   4. putting a job into the queue (see {JobExtension::ClassMethods.create});
    #   5. fetching the job from the queue to perform (see {JobExtension::ClassMethods.reserve});
    #   6. finishing the job peforming (see {JobExtension#after_perform_check_unique_lock} and {JobExtension#on_failure_check_unique_lock}
    #   7. also, removing of jobs and queues, to cleanup orphaned locks (see {ResqueExtension} and {JobExtension.destroy}).
    # At those points, the lock is set, checked or cleaned, according to job's lock type (see below), via Redis keys unique for this combination of job's class and arguments.
    #
    # Using and configuring:
    #   class MyWorker
    #     include Resque::Plugins::Uniqueness
    #
    #     @lock_type = <desired_type> # :until_executing, :while_executing, :until_and_while_executing or :none
    module Uniqueness
      REDIS_KEY_PREFIX = 'resque_uniqueness'

      LOCKS = {
        until_executing: UntilExecuting,
        while_executing: WhileExecuting,
        until_and_while_executing: UntilAndWhileExecuting,
        none: None
      }.freeze

      @default_lock_type = :until_executing

      class << self
        attr_accessor :default_lock_type

        def included(base)
          base.extend ClassMethods
        end

        # Resque uses `Resque.pop(queue)` for retrieving jobs from queue,
        # but in case when we have while_executing lock we should to wait when the same job will finish,
        # before we pop the new same job.
        # That's why we should to find the first appropriate job and remove it from queue.
        def pop_perform_unlocked_from_queue(queue)
          payload = Resque.data_store.everything_in_queue(queue).find(&method(:perform_unlocked?))

          job = payload && Resque::Job.new(queue, Resque.decode(payload))
          remove_job_from_queue(queue, job)
          job
        end

        def perform_unlocked?(item)
          !Resque::Job.new(nil, Resque.decode(item)).uniqueness.perform_locked?
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
          job.uniqueness.ensure_unlock_schedule
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

      # Helper methods and callbacks for jobs
      module ClassMethods
        # Callback which skip enqueue when job locked (returns false, resque skip enqueue step, when any from callbacks will return false)
        def before_enqueue_check_lock_availability(*args)
          Resque.inline? || call_from_scheduler? || job_available_for_schedule?(args)
        end

        # Callback which skip schedule when job is locked on schedule
        def before_schedule_check_lock_availability(*args)
          Resque.inline? || job_available_for_schedule?(args)
        end

        # Callback which lock job on schedule if this job should be locked
        def after_schedule_lock_schedule_if_needed(*args)
          return true if Resque.inline?

          create_job(args).uniqueness.try_lock_schedule
        end

        # Resque call this hook after performing
        def after_perform_check_unique_lock(*args)
          create_job(args).uniqueness.ensure_unlock_perform
        end

        # when perform fails Resque call this hook
        def on_failure_check_unique_lock(*args)
          create_job(args).uniqueness.ensure_unlock_perform
        end

        # Simply returns lock type of current job. If instance_variable `@lock_type` is not set, set it to default value
        def lock_type
          @lock_type ||= Resque::Plugins::Uniqueness.default_lock_type
          unless LOCKS.key?(@lock_type)
            raise NameError, "Unexpected lock type. Available lock types: #{LOCKS.keys}, current lock type: #{@lock_type}"
          end

          @lock_type
        end

        # Simple hack.
        # We don't need to skip enqueue step for jobs, which runned from scheduler.
        # Base flow for scheduled jobs:
        #   Resque.enqueue_at -> Resque.enqueue_to (this step could be missed) -> Resque::Job.create -> Resque::Job#perform
        # When we have an `until_executing` lock, and tryig to enqueue or create new same job, we just ignore this job.
        # And in result we ignore jobs which are already locked and should be processed.
        # We can't schedule two same jobs with `until_executing` lock.
        # That's why we sure, that all jobs, which comes from scheduler, should be processed.
        def call_from_scheduler?
          caller.grep(%r{lib/resque/scheduler\.rb.*enqueue}).any?
        end

        private

        def job_available_for_schedule?(args)
          !create_job(args).uniqueness.locked_on_schedule?
        end

        def create_job(args)
          Resque::Job.new(nil, 'class' => name, 'args' => args)
        end
      end
    end
  end
end

# Clear all executing locks from redis (could be present because of unexpected terminated)
Resque::Plugins::Uniqueness::Base.clear_executing
