# frozen_string_literal: true

require 'resque'
require 'resque-scheduler'
require 'resque_scheduler_unique_jobs/version'
require 'resque_scheduler_unique_jobs/lock/base'
require 'resque_scheduler_unique_jobs/lock/while_executing'
require 'resque_scheduler_unique_jobs/lock/until_executing'
require 'resque_scheduler_unique_jobs/lock/until_and_while_executing'
require 'resque_scheduler_unique_jobs/job'
require 'resque_scheduler_unique_jobs/plugins/scheduler_unique_job'
require 'resque_ext/job'

Resque.redis = 'localhost:6379/resque_scheduler_unique_jobs_test' if ENV['REDIS_ENV'] == 'test'

# Base gem module
module ResqueSchedulerUniqueJobs
  REDIS_KEY_PREFIX = 'resque_scheduler_unique_jobs'
  EXECUTING_REDIS_KEY_PREFIX = 'executing'
  SCHEDULED_REDIS_KEY_PREFIX = 'scheduled'

  @default_lock = :until_executing

  class << self
    attr_accessor :default_lock
  end

  Lock::Base.clear_executing
end
