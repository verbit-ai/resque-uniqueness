# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::UntilExecuting do
  let(:job) { Resque::Job.new(nil, 'class' => klass, 'args' => []) }
  let(:lock_instance) { described_class.new(job) }
  let(:redis_key) { lock_instance.send(:redis_key) }
  let(:klass) { UntilExecutingWorker }

  describe '#queueing_locked?' do
    subject { lock_instance.queueing_locked? }

    context 'when already queueing' do
      before { Resque.redis.incr(redis_key) }

      it { is_expected.to be true }
    end

    context 'when not queueing' do
      it { is_expected.to be false }
    end
  end

  describe '#try_lock_queueing' do
    subject(:call) { lock_instance.try_lock_queueing }

    it 'increment data in redis' do
      call
      expect(Resque.redis.get(redis_key)).to eq '1'
    end

    context 'when already locked' do
      before { Resque.redis.incr(redis_key) }

      its_block {
        is_expected.to raise_error(Resque::Plugins::Uniqueness::LockingError, /already locked/)
      }
    end
  end

  describe '#ensure_unlock_queueing' do
    subject(:call) { lock_instance.ensure_unlock_queueing }

    its_block { is_expected.not_to send_message(lock_instance.redis, :del) }

    context 'when locked' do
      before { Resque.redis.incr(redis_key) }

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
      before { Resque.redis.incr(redis_key) }

      its_block { is_expected.not_to raise_error }
    end
  end
end
