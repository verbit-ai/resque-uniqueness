# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::Base do
  describe '.clear_executing' do
    subject(:call) { described_class.clear_executing }

    before do
      stub_const('Resque::Plugins::Uniqueness::WhileExecuting::PREFIX', 'executing')
      stub_const('Resque::Plugins::Uniqueness::REDIS_KEY_PREFIX', 'redis_key_prefix')

      5.times { Resque.redis.incr("#{key_prefix}#{SecureRandom.uuid}") }
    end

    let(:key_prefix) { "#{Resque::Plugins::Uniqueness::WhileExecuting::PREFIX}:#{Resque::Plugins::Uniqueness::REDIS_KEY_PREFIX}:" }

    it 'not include any executing keys' do
      call
      expect(Resque.redis.keys).not_to include(/#{key_prefix}/)
    end
  end
end
