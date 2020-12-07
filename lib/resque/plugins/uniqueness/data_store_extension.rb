# frozen_string_literal: true

module Resque
  module Plugins
    module Uniqueness
      # Extension for Resque::DataStore class
      module DataStoreExtension
        def exists?(key)
          if Redis.current.respond_to?(:exists?)
            # Supporting new redis version.
            @redis.exists?(key)
          else
            # Supporting old redis version. In the new one this method was renamed to "exists?"
            # and "exists" - returns 0 or 1, instead of true/false
            @redis.exists(key)
          end
        end
      end
    end
  end
end
