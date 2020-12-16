# frozen_string_literal: true

RSpec.describe 'Retry check', type: :acceptance do
  describe 'Unreleased locks' do
    before do
      uuids = (1..500).map { SecureRandom.uuid }
      500.times do |i|
        Resque.enqueue_in(rand(0..15), RetryAcceptanceWorker, uuids[i])
      end

      Thread.new do
        10.times do
          sleep 2
          500.times do |i|
            Resque.enqueue_in(rand(0..15), RetryAcceptanceWorker, uuids[i])
          end
          Resque::Worker.new('123').prune_dead_workers
        end
      end

      workers_waiter
    end

    it('is empty', :aggregate_failures) do
      expect(Resque::Plugins::Uniqueness::JobsExtractor.with_unreleased_queueing_lock).to eq []
      expect(Resque.redis.keys('teimstamps:*')).to eq []
    end
  end
end
