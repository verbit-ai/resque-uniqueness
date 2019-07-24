# frozen_string_literal: true

RSpec.describe Resque::Uniqueness::Lock::Base do
  describe '.clear_executing' do
    subject(:call) { described_class.clear_executing }

    before do
      stub_const('Resque::Uniqueness::EXECUTING_REDIS_KEY_PREFIX', 'executing')
      stub_const('Resque::Uniqueness::REDIS_KEY_PREFIX', 'redis_key_prefix')

      5.times { Resque.redis.incr("#{key_prefix}#{SecureRandom.uuid}") }
    end

    let(:key_prefix) { "#{Resque::Uniqueness::EXECUTING_REDIS_KEY_PREFIX}:#{Resque::Uniqueness::REDIS_KEY_PREFIX}:" }

    it 'not include any executing keys' do
      call
      expect(Resque.redis.keys).not_to include(/#{key_prefix}/)
    end
  end

  describe '#plugin_activated?' do
    subject { described_class.new(job).send(:plugin_activated?) }

    let(:job) { Resque::Job.new(nil, 'class' => klass, args: []).uniqueness }

    context 'when klass include plugin' do
      let(:klass) do
        class IncludedPlugin
          include ::Resque::Plugins::Uniqueness
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
