# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

require 'resque/plugins/uniqueness'
require 'resque/tasks'
require 'resque/scheduler/tasks'

require_relative 'spec/tasks'

# NOTE: We need it here, because if we place it into the task body - it does not work.
#       So, please, use this rakefile only for the specs.
require_relative 'spec/spec_helper'
# We need to run this workers in the real resque rake tasks for acceptance specs
Resque.redis = 'localhost:6379/resque_uniqueness_test'
Resque.logger.level = :info

RSpec::Core::RakeTask.new(:spec)

task default: :spec
