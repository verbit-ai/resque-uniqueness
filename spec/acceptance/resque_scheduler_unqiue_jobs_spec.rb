# frozen_string_literal: true

require 'securerandom'
require_relative '../fixtures/test_workers'

RSpec.describe ResqueSchedulerUniqueJobs do
  subject do
    3.times { Resque.enqueue_in(2, worker_class, uniq_argument) }
    3.times { Resque.enqueue(worker_class, uniq_argument) }
    3.times { Resque.enqueue_to(:other_queue, worker_class, uniq_argument) }
    workers_waiter
    Resque.redis.get(TestWorker::REDIS_KEY)
  end

  before { Resque.redis.del(TestWorker::REDIS_KEY) }

  let(:uniq_argument) { SecureRandom.uuid }
  let(:displayed_argument) { [uniq_argument].to_json }
  let(:starting_worker_output) { "Starting processing #{worker_class} with args: #{displayed_argument}" }
  let(:ending_worker_output) { "Ending processing #{worker_class} with args: #{displayed_argument}" }

  describe 'default_lock' do
    subject { described_class.default_lock }

    before { described_class.instance_variable_set(:@default_lock, :while_executing) }

    it { is_expected.to eq :while_executing }
  end

  describe 'while_executing' do
    let(:worker_class) { WhileExecutingWorker }

    let(:output_result) do
      str = ''
      9.times do
        str += starting_worker_output
        str += ending_worker_output
      end
      str
    end

    it { is_expected.to eq output_result }
  end

  describe 'until_executing' do
    let(:worker_class) { UntilExecutingWorker }

    let(:output_result) do
      str = starting_worker_output
      str += ending_worker_output
      str
    end

    it { is_expected.to eq output_result }
  end

  describe 'until_and_while_executing' do
    subject do
      Resque.enqueue(worker_class, uniq_argument)
      scheduled_workers_waiter
      super()
    end

    let(:worker_class) { UntilAndWhileExecutingWorker }

    let(:output_result) do
      str = ''
      # one from super subject and one from main subject
      2.times do
        str += starting_worker_output
        str += ending_worker_output
      end
      str
    end

    it { is_expected.to eq output_result }
  end

  def workers_waiter
    working_keys = %w[delayed: queue: test_worker_performing:]
    working_jobs = /(#{working_keys.join(')|(')})/
    sleep 1 until Resque.redis.keys.grep(working_jobs).empty?
  end

  def scheduled_workers_waiter
    scheduled_keys = %w[delayed: queue:]
    scheduled_jobs = /(#{scheduled_keys.join(')|(')})/
    sleep 1 until Resque.redis.keys.grep(scheduled_jobs).empty?
  end
end
