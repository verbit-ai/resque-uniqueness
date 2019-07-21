# frozen_string_literal: true

RSpec.describe ResqueSchedulerUniqueJobs::Lock::Base do
  describe '.clear_executing' do
    subject(:call) { described_class.clear_executing }

    before do
      stub_const('ResqueSchedulerUniqueJobs::EXECUTING_REDIS_KEY_PREFIX', 'executing')
      stub_const('ResqueSchedulerUniqueJobs::REDIS_KEY_PREFIX', 'redis_key_prefix')

      5.times { Resque.redis.incr("#{key_prefix}#{SecureRandom.uuid}") }
    end

    let(:key_prefix) { "#{ResqueSchedulerUniqueJobs::EXECUTING_REDIS_KEY_PREFIX}:#{ResqueSchedulerUniqueJobs::REDIS_KEY_PREFIX}:" }

    it 'not include any executing keys' do
      call
      expect(Resque.redis.keys).not_to include(/#{key_prefix}/)
    end
  end

  describe '#plugin_activated?' do
    subject { described_class.new(job).send(:plugin_activated?) }

    let(:job) { Resque::Job.new(nil, 'class' => klass, args: []).uniq_wrapper }

    context 'when klass include plugin' do
      let(:klass) do
        class IncludedPlugin
          include ::Resque::Plugins::SchedulerUniqueJob
        end
        IncludedPlugin
      end

      it { is_expected.to be true }
    end

    context 'when klass include plugin' do
      let(:klass) do
        class NotIncludedPlugin; end
        NotIncludedPlugin
      end

      it { is_expected.to be false }
    end
  end
end
