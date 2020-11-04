# frozen_string_literal: true

require 'securerandom'

module Resque
  module Plugins
    module Uniqueness
      # Resque::Uniqueness increases the delay between poping item from the queue and pushing item
      # into worker processing redis key. (We need to check locks, unlocking queueing, locking
      # performing and etc, between these two steps)
      # So, with it we increase the chance, that worker could be killed in the most inappropriate
      # moment: When it was poped from the queue, and when not pushed to the worker redis key.
      # If Resque::Worker will be killed in this time - the job will lose. In some cases - job
      # lose, but uniqueness key - don't.
      # So - it's definately a bug.
      # This module incapsulate logic to storing jobs, which was poped from the queue in redis.
      # The job removes from the redis - when it will be placed into the worker redis key.
      module RecoveringQueue
        extend self

        REDIS_KEY_PREFIX = 'resque:recovering:queue:'
        REDIS_KEY = "#{REDIS_KEY_PREFIX}%{queue}"

        # How many seconds item could be in the recovering queue.
        # If more - the item is definately broken.
        ALLOWED_DELAY = 3

        # Unique que, passed into item payload
        UUID_KEY = :recovering_uuid

        # Queues, on which we trying to use a recovering queue functionality
        ALLOWED_QUEUES_REDIS_KEY = 'recovering:allowed:queues'

        # Should be pushed definately after the job was taken from the queue
        # NOTE: This method modify item, and add uuid to it.
        def push(queue, item)
          return unless in_allowed_queues?(queue)

          item[UUID_KEY] = SecureRandom.uuid

          Resque.redis
                .zadd(REDIS_KEY % {queue: queue}, Time.now.to_i, Resque.encode(item))
                .tap {
                  Resque.logger.info('Pushed item to the recovering queue. ' \
                                     "Queue: #{queue}. Item: #{item}.")
                }
        end

        # Removed when job placed into the worker redis key, or placed back to queue, or removed
        # from queue manually.
        def remove(queue, item)
          # If this key missed - job not in the recovering queue
          return unless item.transform_keys(&:to_sym).key?(UUID_KEY)

          Resque.logger.info('Removing item from the recovering queue. ' \
                             "Queue: #{queue}. Item: #{item}")
          Resque.redis.zrem(REDIS_KEY % {queue: queue}, Resque.encode(item))
          item.delete(UUID_KEY) || item.delete(UUID_KEY.to_s)
        end

        # Should be run once in the before_first_fork resque hook
        def recover_all
          allowed_queues
            .map { |key| key.to_s.sub(REDIS_KEY_PREFIX, '') }
            .each(&method(:recover))
        end

        def in_allowed_queues?(queue)
          allowed_queues.include?(queue.to_sym)
        end

        private

        def recover(queue)
          items = pop_broken_jobs(queue)
          return if items.empty?

          Resque.logger.info('Found broken jobs in the recovering queue. ' \
                             "Queue: #{queue}. Jobs: #{items}")
          items.map { |item| Resque::Job.new(queue, item) }
               .each(&:ensure_enqueue)
        end

        def pop_broken_jobs(queue)
          args = [REDIS_KEY % {queue: queue}, '-inf', Time.now.to_i - ALLOWED_DELAY]
          Resque.redis.multi {
            Resque.redis.zrangebyscore(*args)
            Resque.redis.zremrangebyscore(*args)
          }.first.map(&Resque.method(:decode))
        end

        def allowed_queues
          @allowed_queues ||= Resque.redis.smembers(ALLOWED_QUEUES_REDIS_KEY).map(&:to_sym)
        end
      end
    end
  end
end
