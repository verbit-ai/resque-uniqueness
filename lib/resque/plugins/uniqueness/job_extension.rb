# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Extension for Resque::Job class
      # Override create, reserve, destroy and perform methods for allowing to work with lock
      # And adding uniqueness wrapper to the Resque::Job
      module JobExtension
        def self.prepended(base)
          class << base
            prepend ClassMethods
          end
        end

        # Class methods for overriding basic Resque::Job class
        module ClassMethods
          # Call before Resque put job into queue
          # We should to ignore locking when this method call from scheduler.
          # More information read in the description of `lib.resque_ext/plugin/scheduler_unique_job.rb#call_from_scheduler?` method
          def create(queue, klass, *args)
            klass = prepare_class(klass)

            # This validate also present in super version of this method, but for be sure
            # that we don't to lock unvalid jobs, we duplicate this validation here
            Resque.validate(klass, queue)

            return super if skip_uniqueness_on_create?(klass)

            job = new(queue, 'class' => klass.to_s, 'args' => decode(encode(args)))

            return if job.uniqueness.queueing_locked?

            job.uniqueness.try_lock_queueing
            super
          rescue LockingError => e
            # In case when two threads locking the same job at the same moment -
            # uniqueness will raise this error for one from them.
            # In this case we should to return nil, but if parent method can handle error -
            # we should to throw it to the parent for preventing to run after hooks.
            raise if parent_handle_locking_error?(e)

            nil
          end

          # Resque call this method, when starting to process job
          # We should to make sure that we starting to process only unlocked jobs.
          # And also we should to be sure that we unlock_queueing and lock performing here
          def reserve(queue)
            return super if Resque.inline?

            job = Resque::Plugins::Uniqueness.pop_perform_unlocked(queue)

            return unless job

            job.uniqueness.ensure_unlock_queueing
            # FIXME: we release lock on queueing and when we push job back to queue (on locking error)
            # we don't set this lock again.
            # This bug shouldn't be reproducable beacuase it works only for `until_and_while_executing` lock type,
            # and in this case we couldn't have two same jobs in queue, but we should to take care on it
            job.uniqueness.try_lock_perform
            job
          rescue LockingError
            # In case when two threads pick up the same job, which don't locked yet,
            # one from them will fail with `LockingError`
            # And in this case we should to push job back
            Resque::Plugins::Uniqueness.push(queue, job.payload)
            nil
          end

          # Destroy with jobs their queueing locks
          # TODO: move logic of releasing locks into Resque::DataStore::QueueAccess#remove_from_queue method
          def destroy(queue, klass, *args)
            unless Resque.inline?
              Resque::Plugins::Uniqueness.unlock_queueing_for(queue, klass, *args)
            end

            super
          end

          private

          # In some cases Resque::Job.create method could to receive string instead of class.
          # For example in Resque::Scheduler plugin, `enqueue_from_config` method
          # after rescue exception
          def prepare_class(klass)
            klass.instance_of?(String) && !klass.empty? ? Resque.constantize(klass) : klass
          end

          def skip_uniqueness_on_create?(klass)
            Resque.inline? ||
              !Resque::Plugins::Uniqueness.enabled_for?(klass) ||
              klass.call_from_scheduler? # klass will contain this method if plugin enabled
          end

          # For now only `Resque.enqueue_to` can and should handle LockingError exception.
          # In case when we don't handle it there - we will run after hooks for job, which don't
          # queued
          # We handle this exception in Resque::Plugins::Uniqueness::ResqueExtension.enqueue_to
          # method
          def parent_handle_locking_error?(error)
            error.backtrace.any? { |trace| trace =~ /resque\.rb.*`enqueue_to/ }
          end
        end

        # This operation ensure that queueing is locked and job placed into queue (or, if it
        # already scheduled, in the schedule)
        # FIXME: This method could be a very slow (see #queued? method). But for now it's used
        #        only for jobs, which needs a recovering. So, realy rarely.
        #        Be sure, if you want to reuse it, rewrite #queued? method, or use it really rarely.
        #        like me.
        def ensure_enqueue
          uniqueness.safe_try_lock_queueing unless uniqueness.queueing_locked?
          return if scheduled? || queued?

          Resque::Plugins::Uniqueness.push(queue, class: payload_class.to_s, args: args)
        end

        def uniqueness
          @uniqueness ||= Resque::Plugins::Uniqueness.fetch_for(self)
        end

        def to_encoded_item_with_queue
          Resque.encode(class: payload_class.to_s, args: args, queue: queue)
        end

        def to_encoded_item
          Resque.encode(class: payload_class.to_s, args: args)
        end

        def to_uniquness_item
          Resque.encode(class: payload_class.uniqueness_key,
                        args: payload_class.unique_args(*args))
        end

        private

        def scheduled?
          Resque.redis.exists?("timestamps:#{to_encoded_item_with_queue}")
        end

        # NOTE: This could be a very slow operation (in case when queue has a lot of jobs), so
        #       use it only if you sure that you need it.
        def queued?
          Resque.redis
                .everything_in_queue(queue)
                .include?(to_encoded_item)
        end
      end
    end
  end
end
