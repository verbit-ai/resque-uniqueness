# frozen_string_literal: true

require 'bundler/setup'
require 'rspec'
require 'saharspec'
require 'rspec/its'
require 'timecop'
require 'resque/plugins/uniqueness'

Resque.redis = 'localhost:6379/resque_uniqueness_test_isolated'
Resque.logger.level = :error

require_relative 'fixtures/test_workers'
require_relative 'acceptance/shared'

Dir[File.join(__dir__, 'helpers', '*.rb')].sort.each { |file| require file }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:context, type: :acceptance) do
    Resque.redis = 'localhost:6379/resque_uniqueness_test'
  end

  config.before do
    Resque.redis.sadd(
      Resque::Plugins::Uniqueness::RecoveringQueue::ALLOWED_QUEUES_REDIS_KEY,
      %i[test_job test_job_recovering]
    )
  end

  config.before(:each, :freeze_current_time) { Timecop.freeze }

  config.after { Timecop.return }
  config.after do
    keys = Resque.redis.keys
    Resque.redis.del(*keys) if keys.any?
  end

  config.after(:context, type: :acceptance) do
    Resque.redis = 'localhost:6379/resque_uniqueness_test_isolated'
  end

  config.include RecoveringQueueHelper, :with_recovering_queue_helper
  config.include QueueHelper, :with_queue_helper
  config.include LockHelper, :with_lock_helper
  config.include ResqueWorkerHelper, :with_resque_worker_helepr
  config.include JobHelper, :with_job_helper
  config.include_context 'when acceptance spec', type: :acceptance
end

RSpec::Matchers.define_negated_matcher :not_to_send_message, :send_message
