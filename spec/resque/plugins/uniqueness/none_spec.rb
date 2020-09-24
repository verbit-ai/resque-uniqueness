# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::None do
  let(:klass) { NoneWorker }
  let(:job) { Resque::Job.new(nil, 'class' => klass, 'args' => []) }
  let(:lock_instance) { described_class.new(job) }
  let(:redis_key) { lock_instance.send(:redis_key) }

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

  describe '#queueing_locked?' do
    subject { lock_instance.queueing_locked? }

    it { is_expected.to be false }
  end

  describe '#try_lock_queueing' do
    subject(:call) { lock_instance.try_lock_queueing }

    its_block { is_expected.not_to raise_error }
  end

  describe '#ensure_unlock_queueing' do
    subject(:call) { lock_instance.ensure_unlock_queueing }

    its_block { is_expected.not_to raise_error }
  end

  describe '#safe_try_lock_queueing' do
    subject(:call) { lock_instance.safe_try_lock_queueing }

    its_block { is_expected.not_to raise_error }
  end
end
