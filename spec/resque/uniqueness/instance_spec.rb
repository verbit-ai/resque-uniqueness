# frozen_string_literal: true

require_relative '../../shared_contexts/with_lock_spec'

RSpec.describe Resque::Uniqueness::Instance do
  let(:queue) { :test_job }
  let(:queue_key) { "queue:#{queue}" }

  describe '#remove_from_queue' do
    subject(:run) { described_class.new(Resque::Job.new(queue, job_payload)).remove_from_queue }

    let(:job) { {class: UntilExecutingWorker, args: [:test]} }
    let(:encoded_job) { Resque.encode(job) }
    let(:job_payload) { Resque.decode(encoded_job) }

    around do |example|
      Resque.redis.lpush(queue_key, [encoded_job, encoded_job])
      example.run
      Resque.redis.del(queue_key)
    end

    it 'removes one job' do
      run
      expect(Resque.redis.lrange(queue_key, 0, -1)).to match_array [encoded_job]
    end
  end
end
