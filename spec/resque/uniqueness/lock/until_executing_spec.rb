# frozen_string_literal: true

RSpec.describe Resque::Uniqueness::Lock::UntilExecuting do
  let(:job) { Resque::Job.new(nil, 'class' => klass, args: []) }
  let(:lock_instance) { described_class.new(job) }
  let(:redis_key) { lock_instance.send(:redis_key) }
  let(:klass) { UntilExecutingWorker }

  describe '#locked_on_schedule?' do
    subject { lock_instance.locked_on_schedule? }

    context 'when already scheduled' do
      around do |example|
        Resque.redis.incr(redis_key)
        example.run
        Resque.redis.del(redis_key)
      end

      it { is_expected.to be true }
    end

    context 'when not scheduled' do
      it { is_expected.to be false }
    end
  end

  describe '#try_lock_schedule' do
    subject(:call) { lock_instance.try_lock_schedule }

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
        is_expected.to raise_error(Resque::Uniqueness::Lock::LockingError, /already locked/)
      end
    end
  end

  describe '#ensure_unlock_schedule' do
    subject(:call) { lock_instance.ensure_unlock_schedule }

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
