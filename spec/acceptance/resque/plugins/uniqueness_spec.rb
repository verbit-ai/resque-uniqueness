# frozen_string_literal: true

require 'securerandom'

# This acceptance specs wotks with test workers `spec/fixures/test_workers.rb`
# Every worker on perform starting write to redis constant messsage that he starts work with this args.
# And when he finish performing - he write the same message, but about finish processing.
# In this specs we check output results of all workers. That all workers work exactly number of times
# And with correct arguments.
# To wait until all workers will finish work we use methods:
#   - workers_waiter
#   - scheduled_workers_waiter
RSpec.describe Resque::Plugins::Uniqueness do
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

  describe 'default_lock_type' do
    subject { described_class.default_lock_type }

    around do |example|
      described_class.instance_variable_set(:@default_lock_type, :while_executing)
      example.run
      described_class.instance_variable_set(:@default_lock_type, :until_executing)
    end

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

    context 'when raise error on perform' do
      let(:worker_class) { WhileExecutingPerformErrorWorker }

      it { is_expected.to eq output_result }
    end
  end

  describe 'until_executing' do
    let(:worker_class) { UntilExecutingWorker }

    let(:output_result) { starting_worker_output + ending_worker_output }

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

    context 'when raise error on perform' do
      let(:worker_class) { UntilAndWhileExecutingPerformErrorWorker }

      it { is_expected.to eq output_result }
    end
  end

  describe 'unique_args' do
    subject do
      3.times { |i| Resque.enqueue_in(2, worker_class, uniq_argument, uuids[i]) }
      3.times { |i| Resque.enqueue(worker_class, uniq_argument, uuids[i + 3]) }
      3.times { |i| Resque.enqueue_to(:other_queue, worker_class, uniq_argument, uuids[i + 6]) }
      workers_waiter
      Resque.redis.get(TestWorker::REDIS_KEY)
    end

    let(:uuids) { (0..8).map { SecureRandom.uuid } }
    let(:worker_class) { UntilExecutingWithUniqueArgsWorker }
    let(:displayed_argument) { [uniq_argument, uuids[0]].to_json }

    let(:output_result) { starting_worker_output + ending_worker_output }

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
