# frozen_string_literal: true

# In case when resque worker (not job, worker, which process jobs) fails, in the moment when we
# take job to check uniqueness key, we lose this job, but left uniqueness key.
# We should not to lose the jobs. So, we should prevent this behaviour to be sure that all will be
# safe, even when resque worker unexpected break down in the most inappropriate moment.
#
# To test it - I run a lot of workers and kill some from resque inactive workers. As a result -
# all workers should be runned.
# I don't test the uniqueness lock here. So, I always use the different arguments.
#
# NOTE: This is a very slow spec. Be patience, when you run it.
RSpec.describe 'Resque jobs recover', type: :acceptance do
  subject(:output_result) do
    uuids.each { |uuid| Resque.enqueue(worker_class, uuid) }
    workers_waiter(Resque::Plugins::Uniqueness::RecoveringQueue::REDIS_KEY_PREFIX)
    Resque.redis.lrange(result_redis_key, 0, -1)
          .tap { timestamp_formatted }
          .tap { copy_current_redis }
  end

  let(:result_redis_key) { 'workers:finished:uuids' }
  let(:uuids) { (0...1000).map { SecureRandom.uuid } }

  around do |example|
    example_working = true
    10.times do
      Thread.new do
        sleep rand(0.001..2)
        while example_working
          # Take not working worker pid
          worker_pid = `ps aux | grep resque-`.split("\n")
                                             .grep(/Waiting for test_job_recovering/)
                                             .sample
                                             &.split
                                             &.fetch(1)
                                             &.to_i
          next unless worker_pid

          Resque.logger.info "Going to kill worker with pid: #{worker_pid}"
          Process.kill('KILL', worker_pid)
        end
      end
    end

    example.run
    example_working = false
  end

  context 'when until_executing lock' do
    let(:worker_class) { UntilExecutingRecoverWorker }

    it { is_expected.to contain_exactly(*uuids) }
  end
end
