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
          # We should to handle exception here to prevent run after hooks.
          # Read more info `Resque::Plugins::Uniqueness::JobExtension.create` and
          # and `Resque::Plugins::Uniqueness::JobExtension.parent_handle_locking_error?`
          def enqueue_to(queue, klass, *args)
            super
          rescue LockingError
            nil
          end

          def remove_queue(queue)
            super.tap {
              Resque::Plugins::Uniqueness.unlock_queueing_for_queue(queue) unless Resque.inline?
            }
          end

          def remove_delayed_job(encoded_item)
            super.tap do
              unless Resque.inline?
                Resque::Plugins::Uniqueness.unlock_queueing(nil, decode(encoded_item))
              end
            end
          end

          def remove_delayed_job_from_timestamp(timestamp, klass, *args)
            removed_count = super
            # If removed_count > zero we should to unlock queueing for this job
            return removed_count if Resque.inline? || removed_count.zero?

            Resque::Plugins::Uniqueness.unlock_queueing(nil, 'class' => klass.to_s, 'args' => args)
            removed_count
          end
        end
      end
    end
  end
end
