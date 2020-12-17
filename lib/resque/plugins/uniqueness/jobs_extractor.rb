# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Module to provide interface for extracting Resque::Job according to difference state
      module JobsExtractor
        extend self

        # Returns array of Resque::Job with unreleased queueing lock.
        # For large database in the first level it will returns some valid jobs. It could be a few
        # reasons of such behaviour. For example - when it tries to select not scheduled jobs,
        # some jobs moved to the queue at this time, release lock, reschedule and set lock again.
        # So, lock present, job in schedule exists, but system could think that it missed.
        # To prevent such mistakes - I decide just to run this filters few times.
        # Every time the count of locked_items will decrease, so loop cicle will be faster and
        # faster.
        def with_unreleased_queueing_lock(filtering_count = 5)
          locked_items = locked_items_for(UntilExecuting)
          filtering_count.times do |filtering_attempt|
            locked_items = locked_items.then(&method(:select_not_scheduled))
                                       .-(fetch_queued_items)
                                       .then(&method(:select_with_existing_lock))
            break if locked_items.empty?

            # Just a delay to be sure that our filter system is spread by time, and return
            # most relevant data
            # NOTE: "if" - to prevent sleep on the last cycle.
            sleep 1.0 / filtering_count if filtering_attempt + 1 < filtering_count
          end

          locked_items.map(&method(:item_to_job))
        end

        # Locking system is a very dynamic. So, some jobs could be unlocked just now, and that's
        # why we still could think that it locked and job will be in the `unreleased_locks` array.
        # To be sure that you will not have any such cases, I check if lock still present at the
        # end.
        def with_unreleased_performing_lock
          (
            (locked_items_for(WhileExecuting) - performing_items) \
            & locked_items_for(WhileExecuting)
          ).map(&method(:item_to_job))
        end

        def queueing_lock_garbage
          lock_garbage_for(UntilExecuting)
        end

        def performing_lock_garbage
          lock_garbage_for(WhileExecuting)
        end

        # Item is a hash which has a structure:
        #   {'queue' => <queue_name>, 'class' => <worker_class>, 'args' => [<list of args>]}
        def fetch_scheduled_items
          timestamps = redis.zrevrange(:delayed_queue_schedule, 0, -1)
          items = []

          timestamps.each_slice(1000) do |timestamps_part|
            items.push(*scheduled_items_at(timestamps_part))
            logger.info "Already processing items: #{items.count}"
          end
          items.map(&Resque.method(:decode))
        end

        private

        # Item is a hash which has a structure:
        #   {'queue' => <queue_name>, 'class' => <worker_class>, 'args' => [<list of args>]}
        def performing_items
          Resque::Worker
            .working
            .map(&:job)
            .reject(&:empty?)
            .map { |item| item['payload'].merge(item.slice('queue')) }
        end

        def select_not_scheduled(locked_items)
          return [] if locked_items.empty?

          locked_items.zip(
            redis.multi {
              locked_items.each { |item| redis.exists?("timestamps:#{Resque.encode(item)}") }
            }
          ).to_h.reject { |_, is_scheduled| is_scheduled }.keys
        end

        def select_with_existing_lock(locked_items)
          return [] if locked_items.empty?

          locked_items.zip(
            redis.multi {
              locked_items.each { |item|
                job = Resque::Job.new(item['queue'], item.slice('class', 'args'))
                redis.exists?("queueing:resque_uniqueness:#{job.to_uniquness_item}")
              }
            }
          ).to_h.select { |_, is_exist| is_exist }.keys
        end

        # Item is a hash which has a structure:
        #   {'queue' => <queue_name>, 'class' => <worker_class>, 'args' => [<list of args>]}
        def fetch_queued_items
          active_queues = redis.smembers(:queues)

          active_queues
            .zip(redis.multi { active_queues.each(&redis.method(:everything_in_queue)) })
            .to_h
            .flat_map { |queue, items|
              items.map(&Resque.method(:decode))
                   .map { |item| item.merge('queue' => queue) }
            }
        end

        # Item is a hash which has a structure:
        #   {'queue' => <queue_name>, 'class' => <worker_class>, 'args' => [<list of args>]}
        def locked_items_for(lock_class)
          redis.smembers(lock_class.locks_storage_redis_key)
               .then { |redis_keys| redis_keys.empty? ? [] : redis.mget(*redis_keys) }
               .compact
               .map(&Resque.method(:decode))
        end

        # Lock garbage - locks which was still in the locks set, but not actually installed (it's
        #                mean that lock key does not present in redis)
        # I know two expected ways how it could happen:
        #   1. When lock key is expired. Redis automatically delete the key, but it still in the set
        #   2. When someone delete key manually through: Resque.redis.del(redis_key)
        def lock_garbage_for(lock_class)
          redis_keys = redis.smembers(lock_class.locks_storage_redis_key)
          return [] if redis_keys.empty?

          redis_keys
            .zip(redis.mget(redis_keys))
            .to_h
            .select { |_key, val| val.nil? }
            .keys
        end

        def scheduled_items_at(timestamps)
          redis.multi {
            timestamps.each { |timestamp| redis.lrange("delayed:#{timestamp}", 0, -1) }
          }.flatten.compact
        end

        def item_to_job(item)
          Resque::Job.new(item['queue'], item.slice('class', 'args'))
        end

        def logger
          Resque.logger
        end

        def redis
          Resque.redis
        end
      end
    end
  end
end
