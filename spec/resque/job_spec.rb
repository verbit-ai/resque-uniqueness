# frozen_string_literal: true

require_relative '../shared_contexts/with_lock_spec'

# Testing only gem extension to the Resque::Job class
# That's why here I use bad pattern "stubject" - don't repeat it at home :) (Not extension specs)
# I think for this case is a justified
RSpec.describe Resque::Job do
  describe '.create_with_uniq' do
    subject { described_class.create_with_uniq(queue, klass, *args) }

    include_context 'with lock', :locked_on_schedule, :should_lock_on_schedule, :lock_schedule
    let(:lock_class) { ResqueSchedulerUniqueJobs::Lock::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:klass) { UntilAndWhileExecutingWorker }
    let(:args) { ['should_lock_on_schedule'] }

    before { allow(described_class).to receive(:create_without_uniq) }

    its_block { is_expected.to send_message(described_class, :create_without_uniq) }
    its_block { is_expected.to send_message(lock_instance, :lock_schedule) }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.to send_message(described_class, :create_without_uniq) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end

    context 'when called from scheduler' do
      before { allow(klass).to receive(:call_from_scheduler?).and_return(true) }

      its_block { is_expected.to send_message(described_class, :create_without_uniq) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end

    context 'when locked_on_schedule' do
      let(:args) { super().push('locked_on_schedule') }

      its_block { is_expected.not_to send_message(described_class, :create_without_uniq) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end

    context 'when job shouldn\'t lock on schedule' do
      let(:args) { [] }

      its_block { is_expected.to send_message(described_class, :create_without_uniq) }
      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end
  end

  describe '.reserve_with_uniq' do
    subject { described_class.reserve_with_uniq(queue) }

    include_context 'with lock',
                    :locked_on_schedule,
                    :unlock_schedule,
                    :should_lock_on_execute,
                    :lock_execute
    let(:lock_class) { ResqueSchedulerUniqueJobs::Lock::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:job) do
      described_class.new(queue, 'class' => UntilAndWhileExecutingWorker, 'args' => args)
    end
    let(:args) { %w[locked_on_schedule should_lock_on_execute] }

    before do
      allow(ResqueSchedulerUniqueJobs::Job).to receive(:pop_unlocked_on_execute_from_queue)
        .and_return(job)
    end

    its_block { is_expected.to send_message(lock_instance, :unlock_schedule) }
    its_block { is_expected.to send_message(lock_instance, :lock_execute) }
    it { is_expected.to eq job }

    context 'when Resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      before { allow(described_class).to receive(:reserve_without_uniq).and_return(job) }

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

  describe '.destroy_with_uniq' do
    subject { described_class.destroy_with_uniq(queue, klass, *args) }

    let(:queue) { :test_queue }
    let(:klass) { UntilExecutingWorker }
    let(:args) { [] }

    before do
      allow(described_class).to receive(:destroy_without_uniq).and_return(:response)
      allow(ResqueSchedulerUniqueJobs::Job).to receive(:destroy)
    end

    its_block { is_expected.to send_message(described_class, :destroy_without_uniq) }
    its_block { is_expected.to send_message(ResqueSchedulerUniqueJobs::Job, :destroy) }
    it { is_expected.to eq :response }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.to send_message(described_class, :destroy_without_uniq) }
      its_block { is_expected.not_to send_message(ResqueSchedulerUniqueJobs::Job, :destroy) }
      it { is_expected.to eq :response }
    end
  end

  describe '#perform_with_uniq' do
    subject { job.perform_with_uniq }

    include_context 'with lock', :locked_on_execute, :unlock_execute
    let(:lock_class) { ResqueSchedulerUniqueJobs::Lock::WhileExecuting }
    let(:job) do
      described_class.new(:test_queue, 'class' => WhileExecutingWorker, 'args' => args)
    end
    let(:args) { ['locked_on_execute'] }

    before { allow(job).to receive(:perform_without_uniq).and_return(:response) }

    its_block { is_expected.to send_message(job, :perform_without_uniq) }
    its_block { is_expected.to send_message(lock_instance, :unlock_execute) }
    it { is_expected.to eq :response }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.to send_message(job, :perform_without_uniq) }
      its_block { is_expected.not_to send_message(lock_instance, :unlock_execute) }
      it { is_expected.to eq :response }
    end

    context 'when job not locked on execute' do
      let(:args) { [] }

      its_block { is_expected.to send_message(job, :perform_without_uniq) }
      its_block { is_expected.not_to send_message(lock_instance, :unlock_execute) }
      it { is_expected.to eq :response }
    end
  end
end
