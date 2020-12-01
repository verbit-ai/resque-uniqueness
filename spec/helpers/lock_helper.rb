# frozen_string_literal: true

# Some methods to work with locks
module LockHelper
  include BaseHelper
  include JobHelper

  REDIS_KEY_PREFIX = Resque::Plugins::Uniqueness::Base::REDIS_KEY_PREFIX

  def queueing_locked_items
    locked_items.fetch(:queueing, [])
  end

  def performing_locked_items
    locked_items.fetch(:performing, [])
  end

  # Locked items with all lock types
  def locked_items
    Resque.redis
          .keys("*:#{REDIS_KEY_PREFIX}:*")
          .map { |key| key.split(":#{REDIS_KEY_PREFIX}:") }
          .map { |lock_type, item| [lock_type.to_sym, Resque.decode(item).transform_keys(&:to_sym)] }
          .group_by(&:first)
          .transform_values { |val| val.map(&:last) }
  end

  def lock_performing_for(items)
    create_jobs_from(items, nil)
      .map(&:uniqueness)
      .map(&:safe_try_lock_perform)
  end

  def lock_queueing_for(items)
    create_jobs_from(items, nil)
      .map(&:uniqueness)
      .map(&:safe_try_lock_queueing)
  end
end
