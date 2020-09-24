# frozen_string_literal: true

require_relative '../../shared_contexts/with_lock_spec'

RSpec.describe Resque::Plugins::Uniqueness do
  let(:instance) { UntilExecutingWorker }
  let(:queue) { :test_job }
  let(:queue_key) { "queue:#{queue}" }

  ### Specs for plugin extended methods

  describe '.before_enqueue_check_lock_availability' do
    subject { instance.before_enqueue_check_lock_availability(*args) }

    include_context 'with lock', :queueing_locked
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilExecuting }
    let(:args) { ['queueing_locked'] }

    it { is_expected.to be false }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      it { is_expected.to be true }
    end

    context 'when call from scheduler' do
      before { allow(UntilExecutingWorker).to receive(:caller).and_return(['lib/resque/scheduler.rb:248 #enqueue_next_item']) }

      it { is_expected.to be true }
    end

    context 'when job is not locked' do
      let(:args) { ['unlocked'] }

      it { is_expected.to be true }
    end
  end

  describe '.before_schedule_check_lock_availability' do
    subject { instance.before_schedule_check_lock_availability(*args) }

    include_context 'with lock', :queueing_locked, :try_lock_queueing
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilExecuting }
    let(:args) { ['queueing_locked'] }

    it { is_expected.to be false }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      it { is_expected.to be true }
    end

    context 'when job is not locked' do
      let(:args) { ['unlocked'] }

      it { is_expected.to be true }
    end
  end

  describe '.after_perform_check_unique_lock' do
    subject { instance.after_perform_check_unique_lock(*args) }

    include_context 'with lock', :ensure_unlock_perform
    let(:instance) { WhileExecutingWorker }
    let(:lock_class) { Resque::Plugins::Uniqueness::WhileExecuting }
    let(:args) { [] }

    its_block { is_expected.to send_message(lock_instance, :ensure_unlock_perform) }
  end

  describe '.on_failure_check_unique_lock' do
    subject { instance.on_failure_check_unique_lock(RuntimeError.new, *args) }

    include_context 'with lock', :ensure_unlock_perform
    let(:instance) { WhileExecutingWorker }
    let(:lock_class) { Resque::Plugins::Uniqueness::WhileExecuting }
    let(:args) { [] }

    its_block { is_expected.to send_message(lock_instance, :ensure_unlock_perform) }
  end

  describe '.lock_type' do
    subject { instance.lock_type }

    before { stub_const('Resque::Plugins::Uniqueness::LOCKS', until_and_while_executing: UntilAndWhileExecutingWorker, until_executing: UntilExecutingWorker) }

    context 'when @lock_type already set' do
      around do |example|
        instance.instance_variable_set(:@lock_type, :until_and_while_executing)
        example.run
        instance.instance_variable_set(:@lock_type, :until_executing)
      end

      it { is_expected.to eq :until_and_while_executing }
    end

    context 'when lock_type is missing' do
      around do |example|
        instance.instance_variable_set(:@lock_type, nil)
        example.run
        instance.instance_variable_set(:@lock_type, :until_executing)
      end

      before do
        allow(described_class).to receive(:default_lock_type).and_return(:until_and_while_executing)
      end

      it { is_expected.to eq :until_and_while_executing }
    end

    context 'when lock_type is not valid' do
      around do |example|
        instance.instance_variable_set(:@lock_type, :not_valid_lock_type)
        example.run
        instance.instance_variable_set(:@lock_type, :until_executing)
      end

      its_block { is_expected.to raise_error(NameError, /Unexpected lock type\./) }
    end
  end

  describe '.call_from_scheduler?' do
    subject { instance.call_from_scheduler? }

    before { allow(TestWorker).to receive(:caller).and_return(caller_result) }

    context 'when caller backtrace include scheduler enqueue method' do
      let(:caller_result) { ['lib/resque/scheduler.rb:248 #enqueue_next_item'] }

      it { is_expected.to be true }
    end

    context 'when caller backtrace not include scheduler' do
      let(:caller_result) { ['lib/resque/scheduler.rb:248 #not_valid_method'] }

      it { is_expected.to be false }
    end
  end

  ### Specs for class methods

  describe '.pop_perform_unlocked',
           :with_queue_helper,
           :with_recovering_queue_helper,
           :with_job_helper do
    subject(:call) { described_class.pop_perform_unlocked(queue) }

    let(:item) { {class: 'WhileExecutingWorker', args: ['test']} }

    before { push_to_queue(item) }

    its_block { is_expected.to change(&method(:items_in_queue)).from([item]).to([]) }
    its_block {
      is_expected.to change(&method(:items_in_recovering_queue))
        .from([])
        .to([array_including(hash_including(item))])
    }
    it { is_expected.to eq create_job_from(item) }

    context 'when perform locked', :with_lock_helper do
      before { lock_performing_for(item) }

      its_block { is_expected.not_to change(&method(:items_in_queue)) }
      its_block { is_expected.not_to change(&method(:items_in_recovering_queue)) }
      it { is_expected.to be_nil }
    end
  end

  describe '.push', :with_queue_helper, :with_recovering_queue_helper do
    subject(:call) { described_class.push(queue, item) }

    let(:item) { {class: 'UntilExecutingWorker', args: ['test']} }

    its_block { is_expected.not_to change(&method(:items_in_recovering_queue)) }
    its_block { is_expected.to change(&method(:items_in_queue)).from([]).to([item]) }

    context 'when locked on queueing', :with_lock_helper do
      before { lock_queueing_for(item) }

      its_block('ignores lock') { is_expected.to change(&method(:items_in_queue)).from([]).to([item]) }
    end

    context 'when item in the recovering queue' do
      let(:item) { {**super(), described_class::RecoveringQueue::UUID_KEY => 'test_uuid'} }

      before { push_to_recovering_queue(item) }

      its_block {
        is_expected.to change(&method(:items_in_recovering_queue))
          .from([array_including(item)])
          .to([])
      }
      its_block { is_expected.to change(&method(:items_in_queue)).from([]).to([item]) }
    end
  end

  describe '.unlock_queueing_for',
           :with_recovering_queue_helper,
           :with_queue_helper,
           :with_lock_helper do
    subject(:call) { described_class.unlock_queueing_for(queue, klass, *args) }

    let(:klass) { UntilExecutingWorker }
    let(:args) { [1] }
    let(:item) { {class: 'UntilExecutingWorker', args: [1]} }

    before do
      push_to_queue(item)
      lock_queueing_for(item)
    end

    its_block { is_expected.to change(&method(:queueing_locked_items)).from([item]).to([]) }
    its_block { is_expected.not_to change(&method(:items_in_recovering_queue)) }

    context 'when in recovering queue' do
      let(:item) { {**super(), described_class::RecoveringQueue::UUID_KEY => 'test_uuid'} }

      before { push_to_recovering_queue(item) }

      its_block {
        is_expected.to change(&method(:items_in_recovering_queue))
          .from([array_including(item)])
          .to([])
      }
    end

    context 'when class is not match' do
      let(:klass) { WhileExecutingWorker }

      its_block { is_expected.not_to change(&method(:queueing_locked_items)) }
    end

    context "when args doesn't match" do
      let(:args) { [2] }

      its_block { is_expected.not_to change(&method(:queueing_locked_items)) }
    end

    context 'when args are empty' do
      let(:args) { [] }

      its_block { is_expected.to change(&method(:queueing_locked_items)).from([item]).to([]) }
    end
  end

  describe '.unlock_queueing_for_queue',
           :with_recovering_queue_helper,
           :with_queue_helper,
           :with_lock_helper do
    subject { described_class.unlock_queueing_for_queue(queue) }

    let(:items) { (0..2).map { |i| {class: 'UntilExecutingWorker', args: [i]} } }

    before do
      push_to_queue(items)
      lock_queueing_for(items)
    end

    its_block { is_expected.to change(&method(:queueing_locked_items)).from(match_array(items)).to([]) }
    its_block { is_expected.not_to change(&method(:items_in_recovering_queue)) }

    context 'when in recovering queue' do
      let(:items) {
        super().map { |item|
          {**item, described_class::RecoveringQueue::UUID_KEY => item[:args].first}
        }
      }

      before { push_to_recovering_queue(items) }

      its_block {
        is_expected.to change(&method(:items_in_recovering_queue))
          .from(items.map(&method(:array_including)))
          .to([])
      }
    end
  end

  describe '.enabled_for?' do
    subject { described_class.enabled_for?(klass) }

    context 'when klass include plugin' do
      let(:klass) { UntilExecutingWorker }

      it { is_expected.to be true }
    end

    context 'when klass not include plugin' do
      let(:klass) do
        stub_const('WorkerWithoutPlugin',
                   Class.new do
                     def self.perform; end
                   end)
        WorkerWithoutPlugin
      end

      it { is_expected.to be false }
    end
  end
end
