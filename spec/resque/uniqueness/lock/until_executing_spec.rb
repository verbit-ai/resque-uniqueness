# frozen_string_literal: true

RSpec.describe Resque::Uniqueness::Lock::UntilExecuting do
  let(:klass_with_plugin) { UntilExecutingWorker }
  let(:klass_without_plugin) do
    class NotIncludedPlugin
      @lock_type = :until_executing
    end
    NotIncludedPlugin
  end
  let(:job) { Resque::Job.new(nil, 'class' => klass, args: []).uniq_wrapper }
  let(:lock_instance) { described_class.new(job) }
  let(:redis_key) { lock_instance.send(:redis_key) }
  let(:klass) { klass_with_plugin }

  describe '#locked_on_schedule?' do
    subject { lock_instance.locked_on_schedule? }

    context 'when plugin activated and already scheduled' do
      let(:klass) { klass_with_plugin }

      around do |example|
        Resque.redis.incr(redis_key)
        example.run
        Resque.redis.del(redis_key)
      end

      it { is_expected.to be true }
    end

    context 'when plugin activated and not scheduled' do
      let(:klass) { klass_with_plugin }

      it { is_expected.to be false }
    end

    context 'when plugin not activated and not scheduled' do
      let(:klass) { klass_without_plugin }

      it { is_expected.to be false }
    end

    context 'when plugin not activated and already scheduled' do
      let(:klass) { klass_without_plugin }

      around do |example|
        Resque.redis.incr(redis_key)
        example.run
        Resque.redis.del(redis_key)
      end

      it { is_expected.to be false }
    end
  end

  describe '#should_lock_on_schedule?' do
    subject { lock_instance.should_lock_on_schedule? }

    context 'when plugin activated' do
      let(:klass) { klass_with_plugin }

      it { is_expected.to be true }
    end

    context 'when plugin not activated' do
      let(:klass) { klass_without_plugin }

      it { is_expected.to be false }
    end
  end

  describe '#lock_schedule' do
    subject(:call) { lock_instance.lock_schedule }

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

  describe '#unlock_schedule' do
    subject(:call) { lock_instance.unlock_schedule }

    its_block do
      is_expected.to raise_error(Resque::Uniqueness::Lock::UnlockingError, /is not locked/)
    end

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
