# frozen_string_literal: true

require_relative '../../shared_contexts/with_lock_spec'

RSpec.describe Resque::Plugins::Uniqueness do
  let(:instance) { UntilExecutingWorker }
  let(:queue) { :test_job }
  let(:queue_key) { "queue:#{queue}" }

  ### Specs for plugin extended methods

  describe '.before_enqueue_check_lock_availability' do
    subject { instance.before_enqueue_check_lock_availability(*args) }

    include_context 'with lock', :queueing_locked
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilExecuting }
    let(:args) { ['queueing_locked'] }

    it { is_expected.to be false }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      it { is_expected.to be true }
    end

    context 'when call from scheduler' do
      before { allow(UntilExecutingWorker).to receive(:caller).and_return(['lib/resque/scheduler.rb:248 #enqueue']) }

      it { is_expected.to be true }
    end

    context 'when job is not locked' do
      let(:args) { ['unlocked'] }

      it { is_expected.to be true }
    end
  end

  describe '.before_schedule_check_lock_availability' do
    subject { instance.before_schedule_check_lock_availability(*args) }

    include_context 'with lock', :queueing_locked, :try_lock_queueing
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilExecuting }
    let(:args) { ['queueing_locked'] }

    it { is_expected.to be false }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      it { is_expected.to be true }
    end

    context 'when job is not locked' do
      let(:args) { ['unlocked'] }

      it { is_expected.to be true }
    end
  end

  describe '.after_perform_check_unique_lock' do
    subject { instance.after_perform_check_unique_lock(*args) }

    include_context 'with lock', :ensure_unlock_perform
    let(:instance) { WhileExecutingWorker }
    let(:lock_class) { Resque::Plugins::Uniqueness::WhileExecuting }
    let(:args) { [] }

    its_block { is_expected.to send_message(lock_instance, :ensure_unlock_perform) }
  end

  describe '.on_failure_check_unique_lock' do
    subject { instance.on_failure_check_unique_lock(*args) }

    include_context 'with lock', :ensure_unlock_perform
    let(:instance) { WhileExecutingWorker }
    let(:lock_class) { Resque::Plugins::Uniqueness::WhileExecuting }
    let(:args) { [] }

    its_block { is_expected.to send_message(lock_instance, :ensure_unlock_perform) }
  end

  describe '.lock_type' do
    subject { instance.lock_type }

    before { stub_const('Resque::Plugins::Uniqueness::LOCKS', until_and_while_executing: UntilAndWhileExecutingWorker, until_executing: UntilExecutingWorker) }

    context 'when @lock_type already set' do
      around do |example|
        instance.instance_variable_set(:@lock_type, :until_and_while_executing)
        example.run
        instance.instance_variable_set(:@lock_type, :until_executing)
      end

      it { is_expected.to eq :until_and_while_executing }
    end

    context 'when lock_type is missing' do
      around do |example|
        instance.instance_variable_set(:@lock_type, nil)
        example.run
        instance.instance_variable_set(:@lock_type, :until_executing)
      end

      before do
        allow(described_class).to receive(:default_lock_type).and_return(:until_and_while_executing)
      end

      it { is_expected.to eq :until_and_while_executing }
    end

    context 'when lock_type is not valid' do
      around do |example|
        instance.instance_variable_set(:@lock_type, :not_valid_lock_type)
        example.run
        instance.instance_variable_set(:@lock_type, :until_executing)
      end

      its_block { is_expected.to raise_error(NameError, /Unexpected lock type\./) }
    end
  end

  describe '.call_from_scheduler?' do
    subject { instance.call_from_scheduler? }

    before { allow(TestWorker).to receive(:caller).and_return(caller_result) }

    context 'when caller backtrace include scheduler enqueue method' do
      let(:caller_result) { ['lib/resque/scheduler.rb:248 #enqueue'] }

      it { is_expected.to be true }
    end

    context 'when caller backtrace not include scheduler' do
      let(:caller_result) { ['lib/resque/scheduler.rb:248 #not_valid_method'] }

      it { is_expected.to be false }
    end
  end

  ### Specs for class methods

  describe '.pop_perform_unlocked' do
    subject(:unlocked_job) { described_class.pop_perform_unlocked(queue) }

    include_context 'with lock', :perform_locked
    let(:lock_class) { Resque::Plugins::Uniqueness::WhileExecuting }
    let(:jobs) do
      [
        {class: WhileExecutingWorker, args: [:perform_locked]},
        {class: WhileExecutingWorker, args: [:perform_locked]},
        {class: WhileExecutingWorker, args: [:unlocked]}
      ]
    end
    let(:encoded_jobs) { jobs.map(&Resque.method(:encode)) }

    around do |example|
      Resque.redis.lpush(queue_key, encoded_jobs)
      example.run
      Resque.redis.del(queue_key)
    end

    it 'returns correct job and remove it from redis list', :aggregate_failures do
      expect(unlocked_job).to eq Resque::Job.new(queue, Resque.decode(encoded_jobs.last))
      expect(Resque.redis.lrange(queue_key, 0, -1)).to match_array encoded_jobs[0..-2]
    end
  end

  describe '.destroy' do
    subject(:destroy_job) { described_class.destroy(queue, klass, *args) }

    include_context 'with lock', :ensure_unlock_queueing
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilExecuting }
    let(:klass) { UntilExecutingWorker }
    let(:args) { [] }
    let(:jobs) { [job] }
    let(:encoded_jobs) { jobs.map(&Resque.method(:encode)) }

    around do |example|
      Resque.redis.lpush(queue_key, encoded_jobs)
      example.run
      Resque.redis.del(queue_key)
    end

    context 'when class is not match' do
      let(:job) { {class: WhileExecutingWorker, args: [:data]} }

      its_block { is_expected.not_to send_message(lock_instance, :ensure_unlock_queueing) }
    end

    context 'when args doesn\'t match' do
      let(:args) { ['another_data'] }
      let(:job) { {class: klass, args: [:data]} }

      its_block { is_expected.not_to send_message(lock_instance, :ensure_unlock_queueing) }
    end

    context 'when args matches' do
      let(:args) { %w[something_strange] }
      let(:job) { {class: klass, args: %i[something_strange]} }

      its_block { is_expected.to send_message(lock_instance, :ensure_unlock_queueing) }
    end

    context 'when args are empty' do
      let(:args) { [] }
      let(:job) { {class: klass, args: %i[something_strange]} }

      its_block { is_expected.to send_message(lock_instance, :ensure_unlock_queueing) }
    end
  end

  describe '.remove_queue' do
    subject { described_class.remove_queue(queue) }

    include_context 'with lock', :ensure_unlock_queueing
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilExecuting }
    let(:jobs) {}
    let(:encoded_jobs) { jobs.map(&Resque.method(:encode)) }

    around do |example|
      Resque.redis.lpush(queue_key, encoded_jobs)
      example.run
      Resque.redis.del(queue_key)
    end

    context 'when jobs are uniq' do
      let(:jobs) do
        [
          {class: UntilExecutingWorker, args: %i[uniq]},
          {class: UntilExecutingWorker, args: %i[uniq2]}
        ]
      end

      its_block { is_expected.to send_message(lock_instance, :ensure_unlock_queueing).twice }
    end

    context 'when jobs are same' do
      let(:jobs) do
        [
          {class: UntilExecutingWorker, args: %i[same]},
          {class: UntilExecutingWorker, args: %i[same]}
        ]
      end

      its_block { is_expected.to send_message(lock_instance, :ensure_unlock_queueing).once }
    end
  end

  describe '.clear_performing_locks' do
    subject(:call) { described_class.clear_performing_locks }

    before do
      stub_const('Resque::Plugins::Uniqueness::WhileExecuting::PREFIX', 'performing')
      stub_const('Resque::Plugins::Uniqueness::REDIS_KEY_PREFIX', 'redis_key_prefix')

      5.times { Resque.redis.incr("#{key_prefix}#{SecureRandom.uuid}") }
    end

    let(:key_prefix) { "#{Resque::Plugins::Uniqueness::WhileExecuting::PREFIX}:#{Resque::Plugins::Uniqueness::REDIS_KEY_PREFIX}:" }

    it 'not include any performing keys' do
      call
      expect(Resque.redis.keys).not_to include(/#{key_prefix}/)
    end
  end
end
