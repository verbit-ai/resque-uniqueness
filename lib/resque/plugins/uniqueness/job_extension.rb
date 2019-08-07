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
            return super if Resque.inline? || klass.call_from_scheduler?

            job = new(queue, 'class' => klass.to_s, 'args' => decode(encode(args)))

            return if job.uniqueness.queueing_locked?

            job.uniqueness.try_lock_queueing
            super
          end

          # Resque call this method, when starting to process job
          # We should to make sure that we starting to process only unlocked jobs.
          # And also we should to be sure that we unlock_queueing and lock performing here
          def reserve(queue)
            return super if Resque.inline?

            job = Resque::Plugins::Uniqueness.pop_perform_unlocked_from_queue(queue)

            return unless job

            job.uniqueness.ensure_unlock_queueing
            job.uniqueness.try_lock_perform
            job
          end

          # Destroy with jobs their queueing locks
          def destroy(queue, klass, *args)
            super.tap do
              Resque::Plugins::Uniqueness.destroy(queue, klass, *args) unless Resque.inline?
            end
          end
        end

        def uniqueness
          @uniqueness ||= Resque::Plugins::Uniqueness.fetch_for(self)
        end
      end
    end
  end
end