# frozen_string_literal: true

require_relative '../fixtures/test_worker'

RSpec.describe ResqueSchedulerUniqueJobs do
  before { Resque.redis.del(TestWorker::REDIS_KEY) }

  describe 'default_lock' do
    subject { described_class.default_lock }

    before { described_class.instance_variable_set(:@default_lock, :while_executing) }

    it { is_expected.to eq :while_executing }
  end

  describe 'while_executing' do
    subject do
      5.times { Resque.enqueue(TestWorker, 1) }
      resque_workers_waiter
      Resque.redis.get(TestWorker::REDIS_KEY)
    end

    before { TestWorker.instance_variable_set(:@lock, :while_executing) }

    let(:output_result) do
      str = ''
      5.times do
        str += 'Starting processing TestWorker with args: [1]'
        str += 'Ending processing TestWorker with args: [1]'
      end
      str
    end

    it { is_expected.to eq output_result }
  end

  describe 'until_executing' do
    subject do
      5.times { Resque.enqueue_in(1, TestWorker, 1) }
      resque_workers_waiter
      Resque.redis.get(TestWorker::REDIS_KEY)
    end

    before { TestWorker.instance_variable_set(:@lock, :until_executing) }

    let(:output_result) do
      str = 'Starting processing TestWorker with args: [1]'
      str += 'Ending processing TestWorker with args: [1]'
      str
    end

    it { is_expected.to eq output_result }
  end

  def resque_workers_waiter
    working_jobs = /(delayed:)|(queue:test_job)|(resque_scheduler_unique_jobs)/
    sleep 1 until Resque.redis.keys.grep(working_jobs).empty?
  end
end
