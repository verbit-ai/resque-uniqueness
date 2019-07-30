# frozen_string_literal: true

RSpec.describe Resque::Uniqueness::Lock::None do
  let(:klass) { NoneWorker }
  let(:job) { Resque::Job.new(nil, 'class' => klass, args: []) }
  let(:lock_instance) { described_class.new(job) }

  describe '#perform_locked?' do
    subject { lock_instance.perform_locked? }

    it { is_expected.to be false }
  end

  describe '#try_lock_perform' do
    subject(:call) { lock_instance.try_lock_perform }

    its_block { is_expected.not_to raise_error }
  end

  describe '#ensure_unlock_perform' do
    subject(:call) { lock_instance.ensure_unlock_perform }

    its_block { is_expected.not_to raise_error }
  end

  describe '#locked_on_schedule?' do
    subject { lock_instance.locked_on_schedule? }

    it { is_expected.to be false }
  end

  describe '#try_lock_schedule' do
    subject(:call) { lock_instance.try_lock_schedule }

    its_block { is_expected.not_to raise_error }
  end

  describe '#ensure_unlock_schedule' do
    subject(:call) { lock_instance.ensure_unlock_schedule }

    its_block { is_expected.not_to raise_error }
  end
end
