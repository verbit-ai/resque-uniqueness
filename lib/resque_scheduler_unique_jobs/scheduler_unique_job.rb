# frozen_string_literal: true

module Resque
  module Plugins
    # Resque plugin for enable unique jobs
    module SchedulerUniqueJob
      def self.included(base)
        base.extend ClassMethods

        clear_redis
      end

      def self.clear_redis
        Resque.redis.keys.grep(/#{ResqueSchedulerUniqueJobs::REDIS_KEY_PREFIX}/).each { |key| Resque.redis.del(key) }
      end

      # Class methods
      module ClassMethods
        def lock
          @lock ||= :until_executing
        end
      end
    end
  end
end
