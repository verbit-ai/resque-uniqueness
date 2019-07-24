# frozen_string_literal: true

RSpec.describe Resque::Uniqueness::Lock::None do
  let(:klass) { NoneWorker }
  let(:job) { Resque::Job.new(nil, 'class' => klass, args: []).uniq_wrapper }
  let(:lock_instance) { described_class.new(job) }

  describe '#locked_on_execute?' do
    subject { lock_instance.locked_on_execute? }

    it { is_expected.to be false }
  end

  describe '#should_lock_on_execute?' do
    subject { lock_instance.should_lock_on_execute? }

    it { is_expected.to be false }
  end

  describe '#lock_execute' do
    subject(:call) { lock_instance.lock_execute }

    its_block { is_expected.to raise_error(NotImplementedError) }
  end

  describe '#unlock_execute' do
    subject(:call) { lock_instance.unlock_execute }

    its_block { is_expected.to raise_error(NotImplementedError) }
  end

  describe '#locked_on_schedule?' do
    subject { lock_instance.locked_on_schedule? }

    it { is_expected.to be false }
  end

  describe '#should_lock_on_schedule?' do
    subject { lock_instance.should_lock_on_schedule? }

    it { is_expected.to be false }
  end

  describe '#lock_schedule' do
    subject(:call) { lock_instance.lock_schedule }

    its_block { is_expected.to raise_error(NotImplementedError) }
  end

  describe '#unlock_schedule' do
    subject(:call) { lock_instance.unlock_schedule }

    its_block { is_expected.to raise_error(NotImplementedError) }
  end
end
