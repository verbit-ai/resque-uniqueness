# frozen_string_literal: true

require_relative '../../../shared_contexts/with_lock_spec'

# We already prepended this module in `lib/resque/uniqueness.rb`
# Therefore we will test Resque::Job class
RSpec.describe Resque::Plugins::Uniqueness::JobExtension do
  describe '.create' do
    subject { Resque::Job.create(queue, klass, *args) }

    include_context 'with lock', :queueing_locked, :try_lock_queueing
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:klass) { UntilAndWhileExecutingWorker }
    let(:args) { [] }

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
        class WithoutUniquenessPluginWorker
          def self.perform; end
        end
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
  end

  describe '.reserve' do
    subject { Resque::Job.reserve(queue) }

    include_context 'with lock', :ensure_unlock_queueing, :try_lock_perform
    let(:lock_class) { Resque::Plugins::Uniqueness::UntilAndWhileExecuting }
    let(:queue) { :test_queue }
    let(:job) { Resque::Job.new(queue, job_payload) }
    let(:job_payload) { {'class' => UntilAndWhileExecutingWorker, 'args' => args} }
    let(:args) { [] }

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
    subject { Resque::Job.destroy(queue, klass, *args) }

    let(:queue) { :test_queue }
    let(:klass) { UntilExecutingWorker }
    let(:args) { ['sample'] }
    let(:data_store_instance) { instance_double(Resque::DataStore, remove_from_queue: 2) }

    before do
      allow(Resque::Job).to receive(:data_store).and_return(data_store_instance)
      allow(Resque::Plugins::Uniqueness).to receive(:destroy)
    end

    its_block { is_expected.to send_message(data_store_instance, :remove_from_queue).returning(2) }
    its_block { is_expected.to send_message(Resque::Plugins::Uniqueness, :destroy) }
    it { is_expected.to eq 2 }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.to send_message(data_store_instance, :remove_from_queue).returning(2) }
      its_block { is_expected.not_to send_message(Resque::Plugins::Uniqueness, :destroy) }
      it { is_expected.to eq 2 }
    end
  end
end
