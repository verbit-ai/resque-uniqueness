# frozen_string_literal: true

require 'resque/uniqueness'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'resque/tasks'
require 'resque/scheduler/tasks'

require_relative 'spec/fixtures/test_workers'

RSpec::Core::RakeTask.new(:spec)

task default: :spec
