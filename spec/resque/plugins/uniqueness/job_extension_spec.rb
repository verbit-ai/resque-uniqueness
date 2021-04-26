# frozen_string_literal: true

require_relative '../../../shared_contexts/with_lock_spec'

# We already prepended this module in `lib/resque/uniqueness.rb`
# Therefore we will test Resque::Job class
RSpec.describe Resque::Plugins::Uniqueness::JobExtension do
  let(:queue) { klass.instance_variable_get(:@queue) }
  let(:klass) {}
  let(:args) { [] }
  let(:job) { Resque::Job.new(queue, 'class' => klass, 'args' => args) }
  let(:uniqueness) { job.uniqueness }

  describe '.create' do
    subject { Resque::Job.create(queue, klass, *args) }

    include_context 'with lock', :queueing_locked, :try_lock_queueing
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:klass) { UntilAndWhileExecutingWorker }

    before { allow(Resque).to receive(:push) }

    its_block { is_expected.to send_message(Resque, :push).with(queue, class: klass.to_s, args: args) }
    its_block { is_expected.to send_message(lock_instance, :try_lock_queueing) }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      before { allow(Resque::Job).to receive(:new).and_return(job_instance) }

      let(:job_instance) { instance_double(Resque::Job, perform: nil) }

      its_block { is_expected.to send_message(job_instance, :perform) }
      its_block { is_expected.not_to send_message(lock_instance, :try_lock_queueing) }
    end

    context 'when class not include plugin' do
      let(:klass) do
        stub_const('WithoutUniquenessPluginWorker',
                   Class.new do
                     def self.perform; end
                   end)
        WithoutUniquenessPluginWorker
      end

      before { allow(Resque).to receive(:new) }

      its_block { is_expected.to send_message(Resque, :push) }
      its_block { is_expected.not_to send_message(lock_instance, :try_lock_queueing) }
    end

    context 'when called from scheduler' do
      before { allow(klass).to receive(:call_from_scheduler?).and_return(true) }

      its_block { is_expected.to send_message(Resque, :push).with(queue, class: klass.to_s, args: args) }
      its_block { is_expected.not_to send_message(lock_instance, :try_lock_queueing) }
    end

    context 'when queueing_locked' do
      let(:args) { super().push('queueing_locked') }

      its_block { is_expected.not_to send_message(Resque, :push).with(queue, class: klass.to_s, args: args) }
      its_block { is_expected.not_to send_message(lock_instance, :try_lock_queueing) }
    end

    context 'when queue missed in worker' do
      let(:klass) { Class.new(TestWorker) }
      let(:queue) {}

      its_block do
        is_expected.to raise_error(Resque::NoQueueError)
          .and(not_to_send_message(Resque, :push))
          .and(not_to_send_message(lock_instance, :try_lock_queueing))
      end
    end

    context 'when klass is empty' do
      let(:klass) { '' }

      its_block do
        is_expected.to raise_error(Resque::NoClassError)
          .and(not_to_send_message(Resque, :push))
          .and(not_to_send_message(lock_instance, :try_lock_queueing))
      end
    end
  end

  describe 'LockingError' do
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:klass) { UntilAndWhileExecutingWorker }

    include_context 'with lock', :queueing_locked, :try_lock_queueing

    before do
      allow(lock_instance).to receive(:try_lock_queueing)
        .and_raise(Resque::Plugins::Uniqueness::LockingError)
      allow(lock_instance).to receive(:ensure_unlock_queueing)
      allow(lock_instance).to receive(:try_lock_perform)
        .and_raise(Resque::Plugins::Uniqueness::LockingError)
    end

    describe 'Resque::Job.create' do
      subject { Resque::Job.create(queue, klass, *args) }

      its_block { is_expected.not_to raise_error }
    end

    describe 'Resque.enqueue_to' do
      subject { Resque.enqueue_to(queue, klass, *args) }

      its_block { is_expected.not_to raise_error }
    end

    describe 'Resque::Job.reserve' do
      subject { Resque::Job.reserve(queue) }

      let(:job) { Resque::Job.new(queue, job_payload) }
      let(:job_payload) { {'class' => UntilAndWhileExecutingWorker, 'args' => args} }

      before do
        allow(Resque::Plugins::Uniqueness).to receive(:pop_perform_unlocked).and_return(job)
      end

      its_block { is_expected.not_to raise_error }
    end
  end

  describe '.reserve' do
    subject { Resque::Job.reserve(queue) }

    include_context 'with lock', :ensure_unlock_queueing, :try_lock_perform
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:job) { Resque::Job.new(queue, job_payload) }
    let(:job_payload) { {'class' => UntilAndWhileExecutingWorker, 'args' => args} }

    before { allow(Resque::Plugins::Uniqueness).to receive(:pop_perform_unlocked).and_return(job) }

    its_block { is_expected.to send_message(lock_instance, :ensure_unlock_queueing) }
    its_block { is_expected.to send_message(lock_instance, :try_lock_perform) }
    it { is_expected.to eq job }

    context 'when Resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      before { allow(Resque).to receive(:pop).and_return(job_payload) }

      its_block { is_expected.not_to send_message(lock_instance, :ensure_unlock_queueing) }
      its_block { is_expected.not_to send_message(lock_instance, :try_lock_perform) }
      it { is_expected.to eq job }
    end
  end

  describe '.destroy' do
    subject(:destroy) { Resque::Job.destroy(queue, klass, *args) }

    let(:klass) { UntilExecutingWorker }
    let(:args) { ['sample'] }

    before { Resque.enqueue(klass, *args) }

    its_block { is_expected.to change(uniqueness, :queueing_locked?).from(true).to(false) }
    its_block { is_expected.to send_message(Resque::Plugins::Uniqueness, :unlock_queueing_for) }
    it { is_expected.to eq 1 }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.not_to send_message(Resque::Plugins::Uniqueness, :unlock_queueing_for) }
    end
  end

  describe 'instance methods' do
    let(:klass) { UntilExecutingWorker }

    describe '#ensure_enqueue' do
      subject(:call) { job.ensure_enqueue }

      its_block { is_expected.to change(&method(:queueing_locked?)).from(false).to(true) }
      its_block { is_expected.to change(&method(:count_in_queue)).from(0).to(1) }
      its_block { is_expected.not_to change(&method(:count_scheduled)) }
      it { call && (expect(count_scheduled).to eq 0) }

      context 'when queueing locked' do
        before { job.uniqueness.try_lock_queueing }

        its_block { is_expected.not_to change(&method(:queueing_locked?)) }
        it { call && (expect(queueing_locked?).to eq true) }

        its_block { is_expected.to change(&method(:count_in_queue)).from(0).to(1) }
        its_block { is_expected.not_to change(&method(:count_scheduled)) }
        it { call && (expect(count_scheduled).to eq 0) }
      end

      context 'when scheduled' do
        before do
          Resque.enqueue_in(10, job.payload_class, *job.args)
          job.uniqueness.ensure_unlock_queueing
        end

        its_block { is_expected.to change(&method(:queueing_locked?)).from(false).to(true) }

        its_block { is_expected.not_to change(&method(:count_in_queue)) }
        it { call && (expect(count_in_queue).to eq 0) }

        its_block { is_expected.not_to change(&method(:count_scheduled)) }
        it { call && (expect(count_scheduled).to eq 1) }
      end

      context 'when queued' do
        before do
          Resque.enqueue(job.payload_class, *job.args)
          job.uniqueness.ensure_unlock_queueing
        end

        its_block { is_expected.to change(&method(:queueing_locked?)).from(false).to(true) }

        its_block { is_expected.not_to change(&method(:count_in_queue)) }
        it { call && (expect(count_in_queue).to eq 1) }

        its_block { is_expected.not_to change(&method(:count_scheduled)) }
        it { call && (expect(count_scheduled).to eq 0) }
      end

      context 'when queued and queueing locked' do
        before { Resque.enqueue(job.payload_class, *job.args) }

        its_block { is_expected.not_to change(&method(:queueing_locked?)) }
        it { call && (expect(queueing_locked?).to eq true) }

        its_block { is_expected.not_to change(&method(:count_in_queue)) }
        it { call && (expect(count_in_queue).to eq 1) }

        its_block { is_expected.not_to change(&method(:count_scheduled)) }
        it { call && (expect(count_scheduled).to eq 0) }
      end

      def queueing_locked?
        job.uniqueness.queueing_locked?
      end

      def count_in_queue
        encoded_payload = Resque.encode(class: job.payload_class.to_s, args: job.args)
        Resque.redis.everything_in_queue(queue).count { |item| item == encoded_payload }
      end

      def count_scheduled
        encoded_payload = Resque.encode(class: job.payload_class.to_s, args: job.args, queue: queue)
        Resque.redis.scard("timestamps:#{encoded_payload}")
      end
    end

    describe '#to_encoded_item_with_queue' do
      subject { job.to_encoded_item_with_queue }

      let(:klass) { UntilExecutingWorker }

      it { is_expected.to eq({class: klass, args: args, queue: queue}.to_json) }
    end

    describe '#to_encoded_item' do
      subject { job.to_encoded_item }

      let(:klass) { UntilExecutingWorker }

      it { is_expected.to eq({class: klass, args: args}.to_json) }
    end

    describe '#to_uniquness_item' do
      subject { job.to_uniquness_item }

      let(:klass) { UntilExecutingWorker }

      it { is_expected.to eq({class: klass, args: args}.to_json) }
    end
  end
end
