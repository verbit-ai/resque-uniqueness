# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::JobsExtractor do
  describe '.with_unreleased_queueing_lock' do
    subject { described_class.with_unreleased_queueing_lock }

    let(:locked_job) { Resque::Job.new(nil, 'class' => UntilExecutingWorker, 'args' => [1]) }
    let(:queued_locked_job) { Resque::Job.new(nil, 'class' => UntilExecutingWorker, 'args' => [2]) }
    let(:scheduled_locked_job) { Resque::Job.new(nil, 'class' => UntilExecutingWorker, 'args' => [3]) }
    let(:already_unlocked_job) { Resque::Job.new(nil, 'class' => UntilExecutingWorker, 'args' => [4]) }

    before do
      locked_job.uniqueness.try_lock_queueing

      Resque.enqueue(queued_locked_job.payload_class, *queued_locked_job.args)

      Resque.enqueue_in(10, scheduled_locked_job.payload_class, *scheduled_locked_job.args)

      already_unlocked_job.uniqueness.send(:remember_lock)
    end

    it { is_expected.to eq [locked_job] }
  end

  describe '.with_unreleased_performing_lock' do
    subject { described_class.with_unreleased_performing_lock }

    let(:locked_job) { Resque::Job.new(nil, 'class' => WhileExecutingWorker, 'args' => [1]) }
    let(:locked_working_job) { Resque::Job.new(nil, 'class' => WhileExecutingWorker, 'args' => [2]) }
    let(:already_unlocked_job) { Resque::Job.new(nil, 'class' => WhileExecutingWorker, 'args' => [3]) }

    let(:worker) { Resque::Worker.new(:all) }

    before do
      worker.startup
      worker.working_on(locked_working_job)

      locked_working_job.uniqueness.try_lock_perform
      locked_job.uniqueness.try_lock_perform
      already_unlocked_job.uniqueness.send(:remember_lock)
    end

    it { is_expected.to eq [locked_job] }
  end

  describe '.queueing_lock_garbage' do
    subject { described_class.queueing_lock_garbage }

    let(:job_for_garbage) { Resque::Job.new(:test, 'class' => UntilExecutingWorker, 'args' => [1]) }
    let(:job) { Resque::Job.new(:test, 'class' => UntilExecutingWorker, 'args' => [2]) }

    before do
      Resque.enqueue(job_for_garbage.payload_class, *job_for_garbage.args)
      Resque.redis.del(job_for_garbage.uniqueness.redis_key)

      Resque.enqueue(job.payload_class, *job.args)
    end

    it { is_expected.to eq [job_for_garbage.uniqueness.redis_key] }
  end

  describe '.performing_lock_garbage' do
    subject { described_class.performing_lock_garbage }

    let(:job_for_garbage) { Resque::Job.new(:test_job, 'class' => WhileExecutingWorker, 'args' => [1]) }
    let(:job) { Resque::Job.new(:test_job, 'class' => WhileExecutingWorker, 'args' => [2]) }

    before do
      Resque.enqueue(job_for_garbage.payload_class, *job_for_garbage.args)
      Resque.enqueue(job.payload_class, *job.args)
      while Resque::Job.reserve(:test_job); end

      Resque.redis.del(job_for_garbage.uniqueness.redis_key)
    end

    it { is_expected.to eq [job_for_garbage.uniqueness.redis_key] }
  end
end
