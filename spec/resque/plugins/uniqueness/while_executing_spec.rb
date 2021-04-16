# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::WhileExecuting do
  let(:job) { Resque::Job.new(nil, 'class' => klass, args: []) }
  let(:lock_instance) { described_class.new(job) }
  let(:redis_key) { lock_instance.send(:redis_key) }
  let(:klass) { WhileExecutingWorker }

  describe '#perform_locked?' do
    subject { lock_instance.perform_locked? }

    context 'when already performing' do
      around do |example|
        lock
        example.run
        unlock
      end

      it { is_expected.to be true }
    end

    context 'when not performing' do
      it { is_expected.to be false }
    end
  end

  describe '#try_lock_perform' do
    subject(:call) { lock_instance.try_lock_perform }

    its_block {
      is_expected.to change { Resque.redis.get(redis_key) }
        .from(nil)
        .to({class: klass, args: nil, queue: nil}.to_json)
    }

    context 'when already locked' do
      around do |example|
        lock
        example.run
        unlock
      end

      its_block do
        is_expected.to raise_error(Resque::Plugins::Uniqueness::LockingError, /already locked/)
      end
    end
  end

  describe '#ensure_unlock_perform' do
    subject(:call) { lock_instance.ensure_unlock_perform }

    its_block { is_expected.not_to send_message(lock_instance.redis, :del) }

    context 'when locked' do
      around do |example|
        lock
        example.run
        unlock
      end

      it 'remove redis key' do
        call
        expect(Resque.redis.get(redis_key)).to be_nil
      end
    end
  end

  describe '#redis_key' do
    subject { redis_key }

    let(:job) { Resque::Job.new(nil, 'class' => klass, 'args' => [], 'queue' => 'test_queue') }

    it 'not to save queue' do
      is_expected.not_to match(/test_queue/)
    end
  end

  describe '#safe_try_lock_queueing' do
    subject(:call) { lock_instance.safe_try_lock_queueing }

    its_block { is_expected.not_to raise_error }

    # None lock type doesn not have any locks for queueing. So, error will not be raised
    context 'when already locked' do
      before { lock }

      its_block { is_expected.not_to raise_error }
    end
  end

  def lock
    lock_instance.send(:set_lock, described_class::LOCK_EXPIRE_SECONDS)
  end

  def unlock
    lock_instance.send(:remove_lock)
  end
end
