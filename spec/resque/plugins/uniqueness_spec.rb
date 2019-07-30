# frozen_string_literal: true

require_relative '../../shared_contexts/with_lock_spec'

RSpec.describe Resque::Plugins::Uniqueness do
  let(:instance) { UntilExecutingWorker }

  describe '.before_enqueue_check_lock_availability' do
    subject { instance.before_enqueue_check_lock_availability(*args) }

    include_context 'with lock', :locked_on_schedule
    let(:lock_class) { Resque::Uniqueness::Lock::UntilExecuting }
    let(:args) { ['locked_on_schedule'] }

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
      before { allow(UntilExecutingWorker).to receive(:caller).and_return(['lib/resque/scheduler.rb:248 #enqueue']) }

      it { is_expected.to be true }
    end

    context 'when job is not locked' do
      let(:args) { ['unlocked'] }

      it { is_expected.to be true }
    end
  end

  describe '.before_schedule_check_lock_availability' do
    subject { instance.before_schedule_check_lock_availability(*args) }

    include_context 'with lock', :locked_on_schedule
    let(:lock_class) { Resque::Uniqueness::Lock::UntilExecuting }
    let(:args) { ['locked_on_schedule'] }

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

  describe '.after_schedule_lock_schedule_if_needed' do
    subject { instance.after_schedule_lock_schedule_if_needed(*args) }

    include_context 'with lock', :try_lock_schedule
    let(:lock_class) { Resque::Uniqueness::Lock::UntilExecuting }
    let(:args) { ['should_lock_on_schedule'] }

    its_block { is_expected.to send_message(lock_instance, :try_lock_schedule) }

    context 'when Resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.not_to send_message(lock_instance, :try_lock_schedule) }
    end
  end

  describe '.lock_type' do
    subject { instance.lock_type }

    before { stub_const('Resque::Uniqueness::LOCKS', until_and_while_executing: UntilAndWhileExecutingWorker, until_executing: UntilExecutingWorker) }

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
        allow(Resque::Uniqueness).to receive(:default_lock_type).and_return(:until_and_while_executing)
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
      let(:caller_result) { ['lib/resque/scheduler.rb:248 #enqueue'] }

      it { is_expected.to be true }
    end

    context 'when caller backtrace not include scheduler' do
      let(:caller_result) { ['lib/resque/scheduler.rb:248 #not_valid_method'] }

      it { is_expected.to be false }
    end
  end
end
