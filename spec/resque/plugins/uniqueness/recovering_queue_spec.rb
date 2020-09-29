# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::RecoveringQueue, :with_recovering_queue_helper do
  let(:queue) { :test_job }

  describe '.push', :freeze_current_time do
    subject(:call) { described_class.push(queue, item) }

    let(:item) { {class: 'UntilExecutingWorker', args: ['test_arg']} }

    before { allow(SecureRandom).to receive(:uuid).and_return('test_uuid') }

    its_block {
      is_expected.to change { item }
        .from(hash_excluding(described_class::UUID_KEY => 'test_uuid'))
        .to(hash_including(described_class::UUID_KEY => 'test_uuid'))
    }
    its_block {
      is_expected.to change(&method(:items_in_recovering_queue))
        .from([])
        .to([[{**item, described_class::UUID_KEY => 'test_uuid'}, Time.now.to_i]])
    }
  end

  describe '.remove' do
    subject(:call) { described_class.remove(queue, item) }

    let(:item) { {class: 'UntilExecutingWorker', args: ['test_arg'], described_class::UUID_KEY => 'test_uuid'} }

    before { push_to_recovering_queue(item) }

    its_block {
      is_expected.to change(&method(:items_in_recovering_queue))
        .from([array_including(item)])
        .to([])
    }
    its_block { is_expected.to change(item, :keys).from([:class, :args, described_class::UUID_KEY]).to(%i[class args]) }

    context 'when item not in the queue' do
      before { Resque.redis.del(described_class::REDIS_KEY % {queue: queue}) }

      its_block { is_expected.not_to change(&method(:items_in_recovering_queue)) }
      its_block { is_expected.not_to raise_error }
      its_block { is_expected.to change(item, :keys).from([:class, :args, described_class::UUID_KEY]).to(%i[class args]) }
    end

    context 'when keys are string' do
      let(:item) { super().transform_keys(&:to_s) }

      its_block {
        is_expected.to change(&method(:items_in_recovering_queue))
          .from([array_including(item.transform_keys(&:to_sym))])
          .to([])
      }
      its_block { is_expected.to change(item, :keys).from(['class', 'args', described_class::UUID_KEY.to_s]).to(%w[class args]) }
    end

    context 'when uuid key is missed' do
      before { item.delete(described_class::UUID_KEY) }

      its_block { is_expected.not_to change(&method(:items_in_recovering_queue)) }
      its_block { is_expected.not_to change(item, :keys) }
    end
  end

  describe '.recover_all', :freeze_current_time, :with_queue_helper, :with_lock_helper do
    subject(:call) { described_class.recover_all }

    let(:valid_timestamp) { Time.now.to_i - described_class::ALLOWED_DELAY + 1 }
    let(:edge_timestamp) { Time.now.to_i - described_class::ALLOWED_DELAY }
    let(:broken_timestamp) { Time.now.to_i - described_class::ALLOWED_DELAY - 1 }

    let(:items) {
      (0...items_count).map { |i|
        {class: 'UntilExecutingWorker', args: [i], described_class::UUID_KEY => i}
      }
    }
    let(:items_without_recovering_uuid) {
      items.map { |item|
        item.slice(*(item.keys - [described_class::UUID_KEY]))
      }
    }

    context 'when queue without broken jobs' do
      let(:items_count) { 2 }

      before do
        push_to_recovering_queue(items[0], timestamp: valid_timestamp)
        push_to_recovering_queue(items[1], timestamp: valid_timestamp)
      end

      its_block { is_expected.not_to change(&method(:items_in_recovering_queue)) }
      its_block { is_expected.not_to change(&method(:items_in_queue)) }
      its_block { is_expected.not_to change(&method(:queueing_locked_items)) }
    end

    context 'when queue with broken jobs' do
      let(:items_count) { 3 }

      before do
        push_to_recovering_queue(items[0], timestamp: valid_timestamp)
        push_to_recovering_queue(items[1], timestamp: edge_timestamp)
        push_to_recovering_queue(items[2], timestamp: broken_timestamp)
      end

      its_block {
        is_expected.to change(&method(:items_in_recovering_queue))
          .from(match_array([[items[0], valid_timestamp],
                             [items[1], edge_timestamp],
                             [items[2], broken_timestamp]]))
          .to([[items[0], valid_timestamp]])
      }
      its_block {
        is_expected.to change(&method(:items_in_queue))
          .from([])
          .to(match_array(items_without_recovering_uuid[1..2]))
      }
      its_block {
        is_expected.to change(&method(:queueing_locked_items))
          .from([])
          .to(match_array(items_without_recovering_uuid[1..2]))
      }
    end

    context 'when queue with queueing_locked broken jobs' do
      let(:items_count) { 3 }

      before do
        push_to_recovering_queue(items[0], timestamp: valid_timestamp)
        push_to_recovering_queue(items[1], timestamp: edge_timestamp)
        push_to_recovering_queue(items[2], timestamp: broken_timestamp)

        items.each { |item|
          Resque::Job.new(queue, item.transform_keys(&:to_s))
                     .uniqueness
                     .safe_try_lock_queueing
        }
      end

      its_block {
        is_expected.to change(&method(:items_in_recovering_queue))
          .from(match_array([[items[0], valid_timestamp],
                             [items[1], edge_timestamp],
                             [items[2], broken_timestamp]]))
          .to([[items[0], valid_timestamp]])
      }
      its_block {
        is_expected.to change(&method(:items_in_queue))
          .from([])
          .to(match_array(items_without_recovering_uuid[1..2]))
      }
      its_block { is_expected.not_to change(&method(:queueing_locked_items)) }
    end
  end
end
