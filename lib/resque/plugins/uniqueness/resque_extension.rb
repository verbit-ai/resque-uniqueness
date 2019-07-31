# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Extension of main Resque module
      module ResqueExtension
        def self.prepended(base)
          class << base
            prepend ClassMethods
          end
        end

        # Class methods for override base Resque module
        module ClassMethods
          def remove_queue(queue)
            return super if Resque.inline?

            res = false
            Resque.redis.multi do
              res = super
              Resque::Plugins::Uniqueness.remove_queue(queue)
            end
            res
          end

          def remove_delayed_job(encoded_item)
            return super if Resque.inline?

            res = super
            Resque::Plugins::Uniqueness.unlock_schedule(nil, decode(encoded_item))
            res
          end

          def remove_delayed_job_from_timestamp(timestamp, klass, *args)
            removed_count = super
            # If removed_count > zero we should to unlock schedule for this job
            return removed_count if Resque.inline? || removed_count.zero?

            Resque::Plugins::Uniqueness.unlock_schedule(nil, 'class' => klass.to_s, 'args' => args)
            removed_count
          end
        end
      end
    end
  end
end
