# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Extension for Resque Scheduler
      # We prepend it to resque module and override `delayed_push` and `enqueue_at_with_queue`
      # methods from `Resque::Scheduler::DelayingExtensions`
      # for allowing locks to work in multithreading.
      module ResqueSchedulerExtension
        def self.prepended(base)
          class << base
            prepend ClassMethods
          end
        end

        # Class methods for overriding ResqueScheduler behavior
        module ClassMethods
          # Override Resque::Scheduler::DelayingExtensions.enqueue_at_with_queue method
          # See more info in comments for
          # `Resque::Plugins::Uniqueness::ResqueSchedulerExtension.delayed_push` method
          def enqueue_at_with_queue(queue, timestamp, klass, *args)
            res = plugin.run_before_schedule_hooks(klass, *args)

            p "[RS] run_before_schedule_hooks [#{res}] queue: #{queue}, timestamp: #{timestamp}, klass: #{klass}, args: #{args}"

            return false unless res

            if Resque.inline? || timestamp.to_i <= Time.now.to_i
              # Just create the job and let resque perform it right away with
              # inline.  If the class is a custom job class, call self#scheduled
              # on it. This allows you to do things like
              # Resque.enqueue_at(timestamp, CustomJobClass, :opt1 => val1).
              # Otherwise, pass off to Resque.
              if klass.respond_to?(:scheduled)
                klass.scheduled(queue, klass.to_s, *args)
              else
                Resque.enqueue_to(queue, klass, *args)
              end
            else
              delayed_push(timestamp, job_to_hash_with_queue(queue, klass, args)).tap do |res|
                p "[RS] Delayed push res: #{res} - #{Time.current}"
              end
            end

            plugin.run_after_schedule_hooks(klass, *args)
          rescue LockingError
            false
          end

          # Override Resque::Scheduler::DelayingExtensions.delayed_push
          # We couldn't lock job in the after hook, because of multithreading app can take same jobs
          # at the same time, and only on locking one from them will raise exception.
          # But it will be after the thread will put job to the schedule.
          #
          # We couldn't lock job in the before hook as well, because of next hooks can return false
          # and the job will have lock, but not been scheduled.
          def delayed_push(timestamp, item)
            p "[RS] delayed_push timestamp: #{timestamp}, item: #{item}"
            # This line could raise `LockingError` and it should be handled in the
            # `enqueue_at_with_queue` method
            #
            # We can't handle exception here, because of jobs, which raise an error on locking
            # will run after hooks, but its unexpected behavior.
            Resque.redis.multi do
              Resque::Job.new(item[:queue], 'class' => item[:class], 'args' => item[:args])
                         .uniqueness
                         .try_lock_queueing

              begin
                # First add this item to the list for this timestamp
                redis.rpush("delayed:#{timestamp.to_i}", encode(item))

                # Store the timestamps at with this item occurs
                redis.sadd("timestamps:#{encode(item)}", "delayed:#{timestamp.to_i}")

                # Now, add this timestamp to the zsets.  The score and the value are
                # the same since we'll be querying by timestamp, and we don't have
                # anything else to store.
                redis.zadd :delayed_queue_schedule, timestamp.to_i, timestamp.to_i
              rescue => e
                p 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE delayed_push'
                p e
              end
            end
          end
        end
      end
    end
  end
end
