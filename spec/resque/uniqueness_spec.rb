# frozen_string_literal: true

require_relative '../shared_contexts/with_lock_spec'

RSpec.describe Resque::Uniqueness do
  let(:queue) { :test_job }
  let(:queue_key) { "queue:#{queue}" }

  describe '.pop_perform_unlocked_from_queue' do
    subject(:unlocked_job) { described_class.pop_perform_unlocked_from_queue(queue) }

    include_context 'with lock', :perform_locked
    let(:lock_class) { Resque::Uniqueness::Lock::WhileExecuting }
    let(:jobs) do
      [
        {class: WhileExecutingWorker, args: [:perform_locked]},
        {class: WhileExecutingWorker, args: [:perform_locked]},
        {class: WhileExecutingWorker, args: [:unlocked]}
      ]
    end
    let(:encoded_jobs) { jobs.map(&Resque.method(:encode)) }

    around do |example|
      Resque.redis.lpush(queue_key, encoded_jobs)
      example.run
      Resque.redis.del(queue_key)
    end

    it 'returns correct job and remove it from redis list', :aggregate_failures do
      expect(unlocked_job).to eq Resque::Job.new(queue, Resque.decode(encoded_jobs.last))
      expect(Resque.redis.lrange(queue_key, 0, -1)).to match_array encoded_jobs[0..-2]
    end
  end

  describe '.unperform_unlocked?' do
    subject { described_class.perform_unlocked?(encoded_job) }

    include_context 'with lock', :perform_locked
    let(:lock_class) { Resque::Uniqueness::Lock::WhileExecuting }
    let(:job) { {class: WhileExecutingWorker, args: job_args} }
    let(:encoded_job) { Resque.encode(job) }

    context 'when job is locked' do
      let(:job_args) { [:perform_locked] }

      it { is_expected.to be false }
    end

    context 'when job is unlocked' do
      let(:job_args) { [:unlocked] }

      it { is_expected.to be true }
    end
  end

  describe '.destroy' do
    subject(:destroy_job) { described_class.destroy(queue, klass, *args) }

    include_context 'with lock', :locked_on_schedule, :unlock_schedule
    let(:lock_class) { Resque::Uniqueness::Lock::UntilExecuting }
    let(:klass) { UntilExecutingWorker }
    let(:args) { [] }
    let(:jobs) { [job] }
    let(:encoded_jobs) { jobs.map(&Resque.method(:encode)) }

    around do |example|
      Resque.redis.lpush(queue_key, encoded_jobs)
      example.run
      Resque.redis.del(queue_key)
    end

    context 'when class is not match' do
      let(:job) { {class: WhileExecutingWorker, args: [:data]} }

      its_block { is_expected.not_to send_message(lock_instance, :unlock_schedule) }
    end

    context 'when args doesn\'t match' do
      let(:args) { ['another_data'] }
      let(:job) { {class: klass, args: [:data]} }

      its_block { is_expected.not_to send_message(lock_instance, :unlock_schedule) }
    end

    context 'when args matches and job locked in schedule' do
      let(:args) { %w[something_strange locked_on_schedule] }
      let(:job) { {class: klass, args: %i[something_strange locked_on_schedule]} }

      its_block { is_expected.to send_message(lock_instance, :unlock_schedule) }
    end

    context 'when args matches and job not locked in schedule' do
      let(:args) { %w[something_strange unlocked] }
      let(:job) { {class: klass, args: %i[something_strange unlocked]} }

      its_block { is_expected.not_to send_message(lock_instance, :unlock_schedule) }
    end

    context 'when args are empty and job locked on schedule' do
      let(:args) { [] }
      let(:job) { {class: klass, args: %i[something_strange locked_on_schedule]} }

      its_block { is_expected.to send_message(lock_instance, :unlock_schedule) }
    end

    context 'when args are empty and job not locked in schedule' do
      let(:args) { [] }
      let(:job) { {class: klass, args: %i[something_strange unlocked]} }

      its_block { is_expected.not_to send_message(lock_instance, :unlock_schedule) }
    end
  end

  describe '.remove_queue' do
    subject { described_class.remove_queue(queue) }

    include_context 'with lock', :locked_on_schedule, :unlock_schedule
    let(:lock_class) { Resque::Uniqueness::Lock::UntilExecuting }
    let(:jobs) {}
    let(:encoded_jobs) { jobs.map(&Resque.method(:encode)) }

    around do |example|
      Resque.redis.lpush(queue_key, encoded_jobs)
      example.run
      Resque.redis.del(queue_key)
    end

    context 'when jobs are locked on schedule' do
      let(:jobs) do
        [
          {class: UntilExecutingWorker, args: %i[locked_on_schedule uniq]},
          {class: UntilExecutingWorker, args: %i[locked_on_schedule uniq2]}
        ]
      end

      its_block { is_expected.to send_message(lock_instance, :unlock_schedule).twice }
    end

    context 'when same jobs are locked on schedule' do
      let(:jobs) do
        [
          {class: UntilExecutingWorker, args: %i[locked_on_schedule same]},
          {class: UntilExecutingWorker, args: %i[locked_on_schedule same]}
        ]
      end

      its_block { is_expected.to send_message(lock_instance, :unlock_schedule).once }
    end

    context 'when jobs are not locked on schedule' do
      let(:jobs) do
        [
          {class: UntilExecutingWorker, args: [:unlocked]},
          {class: UntilExecutingWorker, args: [:unlocked]}
        ]
      end

      its_block { is_expected.not_to send_message(lock_instance, :unlock_schedule) }
    end
  end
end
