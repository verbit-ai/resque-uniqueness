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

    include_context 'with lock', :should_lock_on_schedule, :lock_schedule
    let(:lock_class) { Resque::Uniqueness::Lock::UntilExecuting }
    let(:args) { ['should_lock_on_schedule'] }

    its_block { is_expected.to send_message(lock_instance, :lock_schedule) }

    context 'when job doesn\'t locked' do
      let(:args) { ['unlocked'] }

      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end

    context 'when Resque inline' do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      its_block { is_expected.not_to send_message(lock_instance, :lock_schedule) }
    end
  end

  describe '.lock' do
    subject { instance.lock }

    before { stub_const('Resque::Uniqueness::Job::LOCKS', until_and_while_executing: UntilAndWhileExecutingWorker, until_executing: UntilExecutingWorker) }

    context 'when @lock already set' do
      around do |example|
        instance.instance_variable_set(:@lock, :until_and_while_executing)
        example.run
        instance.instance_variable_set(:@lock, :until_executing)
      end

      it { is_expected.to eq :until_and_while_executing }
    end

    context 'when lock is missing' do
      around do |example|
        instance.instance_variable_set(:@lock, nil)
        example.run
        instance.instance_variable_set(:@lock, :until_executing)
      end

      before do
        allow(Resque::Uniqueness).to receive(:default_lock).and_return(:until_and_while_executing)
      end

      it { is_expected.to eq :until_and_while_executing }
    end

    context 'when lock is not valid' do
      around do |example|
        instance.instance_variable_set(:@lock, :not_valid_lock)
        example.run
        instance.instance_variable_set(:@lock, :until_executing)
      end

      its_block { is_expected.to raise_error(NameError, /Unexpected lock\./) }
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
