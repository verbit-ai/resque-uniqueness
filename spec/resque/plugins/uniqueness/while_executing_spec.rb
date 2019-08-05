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
        Resque.redis.incr(redis_key)
        example.run
        Resque.redis.del(redis_key)
      end

      it { is_expected.to be true }
    end

    context 'when not performing' do
      it { is_expected.to be false }
    end
  end

  describe '#try_lock_perform' do
    subject(:call) { lock_instance.try_lock_perform }

    it 'increment data in redis' do
      call
      expect(Resque.redis.get(redis_key)).to eq '1'
    end

    context 'when already locked' do
      around do |example|
        Resque.redis.incr(redis_key)
        example.run
        Resque.redis.del(redis_key)
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
        Resque.redis.incr(redis_key)
        example.run
        Resque.redis.del(redis_key)
      end

      it 'remove redis key' do
        call
        expect(Resque.redis.get(redis_key)).to be_nil
      end
    end
  end
end
