# frozen_string_literal: true

# Some methods to work with recovering queue in specs
module RecoveringQueueHelper
  include BaseHelper

  REDIS_KEY = Resque::Plugins::Uniqueness::RecoveringQueue::REDIS_KEY

  def push_to_recovering_queue(items, queue: self.queue, timestamp: Time.now.to_i)
    ensure_array(items).each { |item|
      Resque.redis.zadd(REDIS_KEY % {queue: queue}, timestamp, Resque.encode(item))
    }
  end

  def items_in_recovering_queue(queue = self.queue)
    Resque.redis
          .zrange(REDIS_KEY % {queue: queue}, 0, -1, with_scores: true)
          .map { |(item, score)| [Resque.decode(item).transform_keys(&:to_sym), score] }
  end
end
