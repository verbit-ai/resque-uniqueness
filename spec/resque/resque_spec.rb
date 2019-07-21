# frozen_string_literal: true

# Testing only gem extension to the Resque module
# That's why here I use bad pattern "stubject" - don't repeat it at home :) (Not extension specs)
# I think for this case is a justified
RSpec.describe Resque do
  describe '.remove_queue_with_uniq' do
    subject { described_class.remove_queue_with_uniq(:test_queue) }

    before do
      allow(described_class).to receive(:remove_queue_without_uniq).and_return(:response)
      allow(ResqueSchedulerUniqueJobs::Job).to receive(:remove_queue)
    end

    its_block { is_expected.to send_message(described_class, :remove_queue_without_uniq) }
    its_block { is_expected.to send_message(ResqueSchedulerUniqueJobs::Job, :remove_queue) }
    it { is_expected.to eq :response }

    context 'when resque inline' do
      around do |example|
        described_class.inline = true
        example.run
        described_class.inline = false
      end

      its_block { is_expected.to send_message(described_class, :remove_queue_without_uniq) }
      its_block { is_expected.not_to send_message(ResqueSchedulerUniqueJobs::Job, :remove_queue) }
      it { is_expected.to eq :response }
    end
  end

  describe '.remove_delayed_job_with_uniq' do
    subject { described_class.remove_delayed_job_with_uniq(described_class.encode(job)) }

    let(:job) { {class: UntilExecutingWorker, args: []} }

    before do
      allow(described_class).to receive(:remove_delayed_job_without_uniq).and_return(:response)
      allow(ResqueSchedulerUniqueJobs::Job).to receive(:unlock_schedule)
    end

    its_block { is_expected.to send_message(described_class, :remove_delayed_job_without_uniq) }
    its_block { is_expected.to send_message(ResqueSchedulerUniqueJobs::Job, :unlock_schedule) }
    it { is_expected.to eq :response }

    context 'when resque inline' do
      around do |example|
        described_class.inline = true
        example.run
        described_class.inline = false
      end

      its_block { is_expected.to send_message(described_class, :remove_delayed_job_without_uniq) }
      its_block do
        is_expected.not_to send_message(ResqueSchedulerUniqueJobs::Job, :unlock_schedule)
      end
      it { is_expected.to eq :response }
    end
  end

  describe '.remove_delayed_job_from_timestamp_with_uniq' do
    subject { described_class.remove_delayed_job_from_timestamp_with_uniq(1111, UntilExecutingWorker) }

    let(:removed_count) { 1 }

    before do
      allow(described_class).to receive(:remove_delayed_job_from_timestamp_without_uniq)
        .and_return(removed_count)
      allow(ResqueSchedulerUniqueJobs::Job).to receive(:unlock_schedule)
    end

    its_block { is_expected.to send_message(described_class, :remove_delayed_job_from_timestamp_without_uniq).returning(removed_count) }
    its_block { is_expected.to send_message(ResqueSchedulerUniqueJobs::Job, :unlock_schedule) }
    it { is_expected.to eq removed_count }

    context 'when resque inline' do
      around do |example|
        described_class.inline = true
        example.run
        described_class.inline = false
      end

      its_block { is_expected.to send_message(described_class, :remove_delayed_job_from_timestamp_without_uniq).returning(removed_count) }
      its_block { is_expected.not_to send_message(ResqueSchedulerUniqueJobs::Job, :unlock_schedule) }
      it { is_expected.to eq removed_count }
    end

    context 'when removed count is zero' do
      let(:removed_count) { 0 }

      its_block { is_expected.to send_message(described_class, :remove_delayed_job_from_timestamp_without_uniq).returning(removed_count) }
      its_block { is_expected.not_to send_message(ResqueSchedulerUniqueJobs::Job, :unlock_schedule) }
      it { is_expected.to eq removed_count }
    end
  end
end
