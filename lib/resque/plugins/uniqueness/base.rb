# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      class LockingError < StandardError; end

      # Base class for Lock instance
      class Base
        def initialize(job)
          @job = job
        end

        def redis
          job.redis
        end

        def queueing_locked?
          false
        end

        def perform_locked?
          false
        end

        def try_lock_perform
          lock_perform if should_lock_on_perform?
        end

        def ensure_unlock_perform
          unlock_perform if perform_locked?
        end

        def try_lock_queueing
          lock_queueing if should_lock_on_queueing?
        end

        def ensure_unlock_queueing
          unlock_queueing if queueing_locked?
        end

        private

        attr_reader :job

        def should_lock_on_queueing?
          false
        end

        def should_lock_on_perform?
          false
        end

        def lock_perform
          raise NotImplementedError
        end

        def unlock_perform
          raise NotImplementedError
        end

        def lock_queueing
          raise NotImplementedError
        end

        def unlock_queueing
          raise NotImplementedError
        end

        def redis_key
          "#{self.class::PREFIX}:#{REDIS_KEY_PREFIX}:#{Resque.encode(class: job.payload_class, args: job.args)}"
        end

        def log(message)
          Resque.logger.info("#{message} for #{job.payload['class']} with #{job.payload['args']}")
        end
      end
    end
  end
end
