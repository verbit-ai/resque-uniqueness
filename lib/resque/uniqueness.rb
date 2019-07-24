# frozen_string_literal: true

require 'resque'
require 'resque-scheduler'
require_relative 'uniqueness/version'
require_relative 'uniqueness/lock/base'
require_relative 'uniqueness/lock/none'
require_relative 'uniqueness/lock/while_executing'
require_relative 'uniqueness/lock/until_executing'
require_relative 'uniqueness/lock/until_and_while_executing'
require_relative 'uniqueness/job'
require_relative 'uniqueness/job_extension'
require_relative 'uniqueness/resque_extension'
require_relative 'plugins/uniqueness'

Resque.redis = 'localhost:6379/resque_uniqueness_test' if ENV['REDIS_ENV'] == 'test'

Resque.prepend Resque::Uniqueness::ResqueExtension
Resque::Job.prepend Resque::Uniqueness::JobExtension

module Resque
  # Base gem module
  module Uniqueness
    REDIS_KEY_PREFIX = 'resque_uniqueness'
    EXECUTING_REDIS_KEY_PREFIX = 'executing'
    SCHEDULED_REDIS_KEY_PREFIX = 'scheduled'

    @default_lock_type = :until_executing

    class << self
      attr_accessor :default_lock_type
    end

    Lock::Base.clear_executing
  end
end
