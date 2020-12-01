# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Module to provide interface for extracting Resque::Job according to difference state
      module JobsExtractor
        extend self

        # Locking system is a very dynamic. So, some jobs could be unlocked just now, and that's
        # why we still could think that it locked and job will be in the `unreleased_locks` array.
        # To be sure that you will not have any such cases, I check if lock still present at the
        # end.
        def with_unreleased_queueing_lock
          (
            (locked_items_for(UntilExecuting) - queued_items - scheduled_items) \
            & locked_items_for(UntilExecuting)
          ).map(&method(:item_to_job))
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

        private

        # Item is a hash which has a structure:
        #   {'queue' => <queue_name>, 'class' => <worker_class>, 'args' => [<list of args>]}
        def performing_items
          Resque::Worker
            .working
            .map(&:job)
            .map { |item| item['payload'].merge(item.slice('queue')) }
        end

        # Item is a hash which has a structure:
        #   {'queue' => <queue_name>, 'class' => <worker_class>, 'args' => [<list of args>]}
        def queued_items
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
        def scheduled_items
          timestamps = redis.zrevrange(:delayed_queue_schedule, 0, -1)
          items = []

          timestamps.each_slice(1000) do |timestamps_part|
            items.push(*scheduled_items_at(timestamps_part))
            logger.info "Already processing items: #{items.count}"
          end
          items.map(&Resque.method(:decode))
        end

        # Item is a hash which has a structure:
        #   {'queue' => <queue_name>, 'class' => <worker_class>, 'args' => [<list of args>]}
        def locked_items_for(lock_class)
          redis.smembers(lock_class.locks_storage_redis_key)
               .then { |redis_keys| redis.mget(*redis_keys) }
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

        # Needs to customize timeout for large redis data. In other case - for large data when
        # trying to take at least "scheduled_items" redis raise Redis::TimeoutError
        def redis
          @redis ||= Resque.redis
          # Resque::DataStore.new(
          #   Redis::Namespace.new(
          #     Resque.redis.namespace,
          #     redis: Redis.new(**Resque.redis._client.options, timeout: 20)
          #   )
          # )
        end
      end
    end
  end
end
