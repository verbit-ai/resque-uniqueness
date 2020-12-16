# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::JobsExtractor, type: :acceptance do
  # In cases when jobs moves from scheduled to queued the system could think that this job has
  # unreleased lock. But it's not. So, this spec ensure that it will not happen.
  describe '.with_unreleased_queueing_lock' do
    before do
      500.times {
        Resque.enqueue_in(rand(1..15), JobsExtractorAcceptanceWorker, SecureRandom.uuid)
      }
    end

    it('is not have unreleased locks', :aggregate_failures) do
      workers_waiter do
        expect(described_class.with_unreleased_queueing_lock(10)).to eq []
      end

      expect(described_class.with_unreleased_queueing_lock(10)).to eq []
      expect(Resque.redis.keys('teimstamps:*')).to eq []
    end
  end
end
