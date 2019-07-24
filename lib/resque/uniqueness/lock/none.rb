# frozen_string_literal: true

module Resque
  module Uniqueness
    module Lock
      # Uses for cases when plugin not included for certain job
      # or when user want to disable uniqueness for certain job
      #   @lock_type = :none
      class None < Base
      end
    end
  end
end
