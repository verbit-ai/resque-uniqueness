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
require_relative 'uniqueness/worker_extension'
require_relative 'uniqueness/resque_extension'
require_relative 'uniqueness/resque_scheduler_extension'
require_relative 'uniqueness/data_store_extension'

require_relative 'uniqueness/recovering_queue'
require_relative 'uniqueness/jobs_extractor'

Resque.prepend Resque::Plugins::Uniqueness::ResqueExtension
Resque::Job.prepend Resque::Plugins::Uniqueness::JobExtension
Resque::Worker.prepend Resque::Plugins::Uniqueness::WorkerExtension
Resque.prepend Resque::Plugins::Uniqueness::ResqueSchedulerExtension
Resque::DataStore.include Resque::Plugins::Uniqueness::DataStoreExtension
Resque.logger = Logger.new(STDOUT, level: :info)

Resque.before_first_fork(&Resque::Plugins::Uniqueness::RecoveringQueue.method(:recover_all))

module Resque
  module Plugins
    # Plugin to ensure Resque job's uniqueness by job class and arguments.
    # It has three modes of uniqueness:
    #   1. until_executing: while the job is in the queue or schedule, no other job of the same class
    #   with the same arguments will be pushed to the queue or scheduled (it would be just ignored);
    #   when the job is starting to perform, the lock is cleared and another job can be pushed
    #   to the queue or scheduled;
    #   2. while_executing: while the job is performing, no other job of the same class with
    #   the same argument will start performing (it will wait in the queue until the one
    #   performing is finished);
    #   3. until_and_while_executing: a combination of the above: while the job is pending,
    #   another one can not be put in the queue or scheduled; and then while it is performing,
    #   another can be pushed, but will not be performed until the current one is finished.
    #
    # It is implemented by providing Resque callbacks where possible, and intercepting (patching)
    # the following places in Resque:
    #   1. Resque::Plugins::Uniqueness is aware of, and compatible with a resque-scheduler gem:
    #   when a job with until_executing or until_and_while_executing lock type is tried to be
    #   scheduled, the before_schedule hook checks it and ignores if one is already in queue.
    #   2. ignoring enqueue (see {Plugins::Uniqueness.before_enqueue_check_lock_availability});
    #   3. putting a job into the queue (see {JobExtension::ClassMethods.create});
    #   4. fetching the job from the queue to perform (see {JobExtension::ClassMethods.reserve});
    #   5. finishing the job peforming (see {JobExtension#after_perform_check_unique_lock} and
    #   {JobExtension#on_failure_check_unique_lock}
    #   6. also, removing of jobs and queues, to cleanup orphaned locks (see {ResqueExtension}
    #   and {JobExtension.destroy}).
    # At those points, the lock is set, checked or cleaned, according to job's lock type (see below),
    # via Redis keys unique for this combination of job's class and arguments.
    #
    # Using and configuring:
    #   class MyWorker
    #     include Resque::Plugins::Uniqueness
    #
    #     # :until_executing, :while_executing, :until_and_while_executing or :none
    #     @lock_type = <desired_type>
    module Uniqueness
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

        # Resque uses `Resque.pop(queue)` for retrieving jobs from queue, but in case when we have
        # while_executing lock we should to be sure that we popped unlocked job.
        # That's why we should to check lock of popped job, and if its locked - push it back.
        def pop_perform_unlocked(queue)
          item = pop(queue) or return

          job = Resque::Job.new(queue, item)
          if job.uniqueness.perform_locked?
            push(queue, item)
            nil
          else
            job
          end
        end

        def push(queue, item)
          return Resque.push(queue, item) unless RecoveringQueue.in_allowed_queues?(queue)

          Resque.redis.multi do
            RecoveringQueue.remove(queue, item)
            Resque.push(queue, item)
          end
        end

        def unlock_queueing_for(queue, klass, *args)
          klass = klass.to_s
          Resque.data_store.everything_in_queue(queue).each do |string|
            item = Resque.decode(string)
            next unless item['class'] == klass
            # Resque destroys all jobs with the certain class if args is empty.
            # That's why we should to check presence of args before comparing it with
            # the args from redis
            next if args.any? && item['args'] != args

            unlock_queueing(queue, item).tap { RecoveringQueue.remove(queue, item) }
          end
        end

        # Unlock queueing for every job in the certain queue
        # NOTE: It's could be a heavy method, so use it only in case, when you should.
        #       Now, used in the Resque.remove_queue method.
        def unlock_queueing_for_queue(queue)
          Resque.data_store.everything_in_queue(queue).uniq.each do |string|
            item = Resque.decode(string)

            unlock_queueing(queue, item).tap { RecoveringQueue.remove(queue, item) }
          end
        end

        def unlock_queueing(queue, item)
          Resque::Job.new(queue, item).uniqueness.ensure_unlock_queueing
        end

        def fetch_for(job)
          lock_key = job.payload_class.respond_to?(:lock_type) ? job.payload_class.lock_type : :none
          LOCKS[lock_key].new(job)
        end

        def enabled_for?(klass)
          klass.included_modules.include?(self)
        end

        private

        def pop(queue)
          Resque.pop(queue)
                .tap { |item| RecoveringQueue.push(queue, item) if item }
        end
      end

      # Helper methods and callbacks for jobs
      module ClassMethods
        # Serialize klass for unique key
        def uniqueness_key
          name
        end

        # Filters args which should be unique
        def unique_args(*args)
          args
        end

        # Callback which skip enqueue when job locked (returns false, resque skip enqueue step,
        # when any from callbacks will return false)
        def before_enqueue_check_lock_availability(*args)
          # Second condition handles the case when the job is already queueing
          # (was allowed to put in queue at the moment of scheduling), and now scheduler moves it
          # from future schedule to queue; if we'll not allow this, job will be lost.
          Resque.inline? || call_from_scheduler? || job_available_for_queueing?(args)
        end

        # Callback which skip schedule when job is locked on queueing
        def before_schedule_check_lock_availability(*args)
          Resque.inline? || job_available_for_queueing?(args)
        end

        # Resque call this hook after performing
        def after_perform_check_unique_lock(*args)
          create_job(args).uniqueness.ensure_unlock_perform
        end

        # when perform fails Resque call this hook
        def on_failure_check_unique_lock(_error, *args)
          create_job(args).uniqueness.ensure_unlock_perform
        end

        # Simply returns lock type of current job. If instance_variable `@lock_type` is not set,
        # set it to default value
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
        #   Resque.enqueue_at -> Resque.enqueue_to (this step could be missed) ->
        #   Resque::Job.create -> Resque::Job#perform
        # When we have an `until_executing` lock, and tryig to enqueue or create new same job,
        # we just ignore this job.
        # And in result we ignore jobs which are already locked and should be processed.
        # We can't schedule two same jobs with `until_executing` lock.
        # That's why we sure, that all jobs, which comes from scheduler, should be processed.
        # However enqueue_to method also calls from rufus scheduled jobs, that's why we should to check
        # method which is specific only for delaying schedule process. This is `enqueue_next_item`
        def call_from_scheduler?
          # This path is from the `resque-scheduler` gem
          # Its not related to resque-uniqueness.
          caller.grep(%r{lib/resque/scheduler\.rb.*enqueue_next_item}).any?
        end

        private

        def job_available_for_queueing?(args)
          !create_job(args).uniqueness.queueing_locked?
        end

        def create_job(args)
          Resque::Job.new(nil, 'class' => name, 'args' => args)
        end
      end
    end
  end
end
