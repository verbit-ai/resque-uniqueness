require 'resque'
require 'resque-scheduler'
require 'resque_scheduler_unique_jobs/version'
require 'resque_scheduler_unique_jobs/job'
require 'resque_scheduler_unique_jobs/scheduler_unique_job'
require 'resque_ext/job'

module ResqueSchedulerUniqueJobs
  REDIS_KEY_PREFIX = 'resque_scheduler_unique_jobs'.freeze
end
