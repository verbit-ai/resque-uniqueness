# frozen_string_literal: true

# We already prepended this module in `lib/resque/uniqueness.rb`
# Therefore we will test Resque module
RSpec.describe Resque::Plugins::Uniqueness::ResqueExtension do
  describe '.remove_queue' do
    subject { Resque.remove_queue(:test_queue) }

    let(:data_store_instance) { instance_double(Resque::DataStore, remove_queue: :response) }

    before do
      allow(Resque).to receive(:data_store).and_return(data_store_instance)
      allow(Resque::Plugins::Uniqueness).to receive(:unlock_queueing_for_queue)
    end

    its_block { is_expected.to send_message(data_store_instance, :remove_queue) }
    its_block { is_expected.to send_message(Resque::Plugins::Uniqueness, :unlock_queueing_for_queue) }
    it { is_expected.to eq :response }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.to send_message(data_store_instance, :remove_queue) }
      its_block { is_expected.not_to send_message(Resque::Plugins::Uniqueness, :unlock_queueing_for_queue) }
      it { is_expected.to eq :response }
    end
  end

  describe '.remove_delayed_job' do
    subject { Resque.remove_delayed_job(Resque.encode(job)) }

    let(:job) { {class: UntilExecutingWorker, args: []} }

    before { allow(Resque::Plugins::Uniqueness).to receive(:unlock_queueing) }

    its_block { is_expected.to send_message(Resque::Plugins::Uniqueness, :unlock_queueing) }
    it { is_expected.to eq 0 }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.not_to send_message(Resque::Plugins::Uniqueness, :unlock_queueing) }
      it { is_expected.to eq 0 }
    end
  end

  describe '.remove_delayed_job_from_timestamp' do
    subject { Resque.remove_delayed_job_from_timestamp(1111, UntilExecutingWorker) }

    let(:removed_count) { 2 }

    before do
      allow(Resque.redis).to receive(:lrem).and_return(removed_count)
      allow(Resque::Plugins::Uniqueness).to receive(:unlock_queueing)
    end

    its_block { is_expected.to send_message(Resque::Plugins::Uniqueness, :unlock_queueing) }
    it { is_expected.to eq 2 }

    context 'when resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.not_to send_message(Resque::Plugins::Uniqueness, :unlock_queueing) }
      it { is_expected.to eq 0 }
    end

    context 'when removed count is zero' do
      let(:removed_count) { 0 }

      its_block { is_expected.not_to send_message(Resque::Plugins::Uniqueness, :unlock_queueing) }
      it { is_expected.to eq 0 }
    end
  end
end
