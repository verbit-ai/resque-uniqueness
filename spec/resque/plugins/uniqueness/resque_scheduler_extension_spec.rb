# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::ResqueSchedulerExtension do
  let(:klass) { UntilExecutingWorker }
  let(:args) { [1] }
  let(:queue) { klass.instance_variable_get(:@queue) }
  let(:job) { Resque::Job.new(queue, 'class' => klass, 'args' => args) }
  let(:redis_key) { job.uniqueness.redis_key }

  describe '.enqueue_in' do
    subject(:schedule) { Resque.enqueue_in(seconds_to_enqueue, klass, *args) }

    let(:seconds_to_enqueue) { 109_000 }

    its_block {
      is_expected.to change { Resque.redis.get(redis_key) }
        .from(nil)
        .to(job.to_encoded_item_with_queue)
    }
    its_block {
      is_expected.to change { Resque.redis.ttl(redis_key) }
        .to(be_within(2).of(seconds_to_enqueue + Resque::Plugins::Uniqueness::UntilExecuting::EXPIRING_TIME))
    }
  end

  describe '.enqueue_at' do
    subject(:schedule) { Resque.enqueue_at(enqueue_timestamp, klass, *args) }

    let(:enqueue_timestamp) { Time.now.to_i + 109_000 }

    its_block {
      is_expected.to change { Resque.redis.get(redis_key) }
        .from(nil)
        .to(job.to_encoded_item_with_queue)
    }
    its_block {
      is_expected.to change { Resque.redis.ttl(redis_key) }
        .to(be_within(2).of(109_000 + Resque::Plugins::Uniqueness::UntilExecuting::EXPIRING_TIME))
    }
  end
end
