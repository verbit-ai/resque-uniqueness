# frozen_string_literal: true

# Some methods to work with queue
module QueueHelper
  include BaseHelper

  def items_in_queue(queue = self.queue)
    Resque.redis
          .everything_in_queue(queue)
          .map(&Resque.method(:decode))
          .map { |item| item.transform_keys(&:to_sym) }
  end

  def push_to_queue(items, queue = self.queue)
    ensure_array(items).each { |item| Resque.push(queue, item) }
  end
end
