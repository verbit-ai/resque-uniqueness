require 'resque_scheduler_unique_jobs'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'resque/tasks'
require 'resque/scheduler/tasks'

require_relative 'spec/fixtures/test_worker'

RSpec::Core::RakeTask.new(:spec)

task default: :spec
