# frozen_string_literal: true

require_relative '../../shared_contexts/with_lock_spec'

# We already prepended this module in `lib/resque/uniqueness.rb`
# Therefore we will test Resque::Job class
RSpec.describe Resque::Uniqueness::JobExtension do
  describe '.create' do
    subject { Resque::Job.create(queue, klass, *args) }

    include_context 'with lock', :locked_on_schedule, :should_lock_on_schedule, :lock_schedule
    let(:lock_class) { Resque::Uniqueness::Lock::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:klass) { UntilAndWhileExecutingWorker }
    let(:args) { ['should_lock_on_schedule'] }

    before { allow(Resque).to receive(:push) }

    its_block { is_expected.to send_message(Resque, :push).with(queue, class: klass.to_s, args: args) }
    its_block { is_expected.to send_message(lock_instance, :lock_schedule) }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      before { allow(Resque::Job).to receive(:new).and_return(job_instance) }

      let(:job_instance) { instance_double(Resque::Job, perform: nil) }

      its_block { is_expected.to send_message(job_instance, :perform) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end

    context 'when called from scheduler' do
      before { allow(klass).to receive(:call_from_scheduler?).and_return(true) }

      its_block { is_expected.to send_message(Resque, :push).with(queue, class: klass.to_s, args: args) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end

    context 'when locked_on_schedule' do
      let(:args) { super().push('locked_on_schedule') }

      its_block { is_expected.not_to send_message(Resque, :push).with(queue, class: klass.to_s, args: args) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end

    context 'when job shouldn\'t lock on schedule' do
      let(:args) { [] }

      its_block { is_expected.to send_message(Resque, :push).with(queue, class: klass.to_s, args: args) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end
  end

  describe '.reserve' do
    subject { Resque::Job.reserve(queue) }

    include_context 'with lock',
                    :locked_on_schedule,
                    :unlock_schedule,
                    :should_lock_on_execute,
                    :lock_execute
    let(:lock_class) { Resque::Uniqueness::Lock::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:job) { Resque::Job.new(queue, job_payload) }
    let(:job_payload) { {'class' => UntilAndWhileExecutingWorker, 'args' => args} }
    let(:args) { %w[locked_on_schedule should_lock_on_execute] }

    before { allow(Resque::Uniqueness).to receive(:pop_unlocked_on_execute_from_queue).and_return(job) }

    its_block { is_expected.to send_message(lock_instance, :unlock_schedule) }
    its_block { is_expected.to send_message(lock_instance, :lock_execute) }
    it { is_expected.to eq job }

    context 'when Resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      before { allow(Resque).to receive(:pop).and_return(job_payload) }

      its_block { is_expected.not_to send_message(lock_instance, :unlock_schedule) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_execute) }
      it { is_expected.to eq job }
    end

    context 'when job is not locked on schedule' do
      before { args.delete('locked_on_schedule') }

      its_block { is_expected.not_to send_message(lock_instance, :unlock_schedule) }
      its_block { is_expected.to send_message(lock_instance, :lock_execute) }
      it { is_expected.to eq job }
    end

    context 'when job is shouldn\'t lock on execute' do
      before { args.delete('should_lock_on_execute') }

      its_block { is_expected.to send_message(lock_instance, :unlock_schedule) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_execute) }
      it { is_expected.to eq job }
    end
  end

  describe '.destroy' do
    subject { Resque::Job.destroy(queue, klass, *args) }

    let(:queue) { :test_queue }
    let(:klass) { UntilExecutingWorker }
    let(:args) { ['sample'] }
    let(:data_store_instance) { instance_double(Resque::DataStore, remove_from_queue: 2) }

    before do
      allow(Resque::Job).to receive(:data_store).and_return(data_store_instance)
      allow(Resque::Uniqueness).to receive(:destroy)
    end

    its_block { is_expected.to send_message(data_store_instance, :remove_from_queue).returning(2) }
    its_block { is_expected.to send_message(Resque::Uniqueness, :destroy) }
    it { is_expected.to eq 2 }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.to send_message(data_store_instance, :remove_from_queue).returning(2) }
      its_block { is_expected.not_to send_message(Resque::Uniqueness, :destroy) }
      it { is_expected.to eq 2 }
    end
  end

  describe '#perform' do
    subject { job.perform }

    include_context 'with lock', :locked_on_execute, :unlock_execute
    let(:lock_class) { Resque::Uniqueness::Lock::WhileExecuting }
    let(:job) { Resque::Job.new(:test_queue, 'class' => WhileExecutingWorker, 'args' => args) }
    let(:args) { ['locked_on_execute'] }

    before { allow(lock_class).to receive(:perform) }

    its_block { is_expected.to send_message(WhileExecutingWorker, :perform) }
    its_block { is_expected.to send_message(lock_instance, :unlock_execute) }
    it { is_expected.to be true }

    context 'when job not locked on execute' do
      let(:args) { [] }

      its_block { is_expected.to send_message(WhileExecutingWorker, :perform) }
      its_block { is_expected.not_to send_message(lock_instance, :unlock_execute) }
      it { is_expected.to eq true }
    end
  end
end
