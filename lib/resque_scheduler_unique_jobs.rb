# frozen_string_literal: true

require 'resque'
require 'resque-scheduler'
require 'resque_scheduler_unique_jobs/version'
require 'resque_scheduler_unique_jobs/lock/base'
require 'resque_scheduler_unique_jobs/lock/while_executing'
require 'resque_scheduler_unique_jobs/lock/until_executing'
require 'resque_scheduler_unique_jobs/job'
require 'resque_scheduler_unique_jobs/scheduler_unique_job'
require 'resque_ext/job'

# Base gem
module ResqueSchedulerUniqueJobs
  REDIS_KEY_PREFIX = 'resque_scheduler_unique_jobs'
  EXECUTING_REDIS_KEY_PREFIX = 'executing'
  SCHEDULED_REDIS_KEY_PREFIX = 'scheduled'

  Lock.clear_executing
end
