# frozen_string_literal: true

require 'bundler/setup'
require 'rspec'
require 'saharspec'
require 'rspec/its'
require 'resque/plugins/uniqueness'

Resque.redis = 'localhost:6379/resque_uniqueness_test'

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

RSpec::Matchers.define_negated_matcher :not_to_send_message, :send_message
