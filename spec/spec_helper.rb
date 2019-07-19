# frozen_string_literal: true

require 'bundler/setup'
require 'saharspec'
require 'rspec/its'

ENV['REDIS_ENV'] = 'test'

require 'resque_scheduler_unique_jobs'
require_relative 'fixtures/test_workers'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
