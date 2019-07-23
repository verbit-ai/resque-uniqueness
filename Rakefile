# frozen_string_literal: true

require 'resque/uniqueness'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'resque/tasks'
require 'resque/scheduler/tasks'

# We need to run this workers in the real resque rake tasks for acceptance specs
require_relative 'spec/fixtures/test_workers'

RSpec::Core::RakeTask.new(:spec)

task default: :spec
