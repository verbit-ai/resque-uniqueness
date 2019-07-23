# frozen_string_literal: true

require 'resque'
require 'resque-scheduler'
require 'resque/uniqueness/version'
require 'resque/uniqueness/lock/base'
require 'resque/uniqueness/lock/while_executing'
require 'resque/uniqueness/lock/until_executing'
require 'resque/uniqueness/lock/until_and_while_executing'
require 'resque/uniqueness/job'
require 'resque/uniqueness/job_extension'
require 'resque/uniqueness/resque_extension'
require 'resque/plugins/uniqueness'

Resque.redis = 'localhost:6379/resque_uniqueness_test' if ENV['REDIS_ENV'] == 'test'

Resque.prepend Resque::Uniqueness::ResqueExtension
Resque::Job.prepend Resque::Uniqueness::JobExtension

module Resque
  # Base gem module
  module Uniqueness
    REDIS_KEY_PREFIX = 'resque_uniqueness'
    EXECUTING_REDIS_KEY_PREFIX = 'executing'
    SCHEDULED_REDIS_KEY_PREFIX = 'scheduled'

    @default_lock = :until_executing

    class << self
      attr_accessor :default_lock
    end

    Lock::Base.clear_executing
  end
end
