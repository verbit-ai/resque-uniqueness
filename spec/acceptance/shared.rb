# frozen_string_literal: true

RSpec.shared_context 'when acceptance spec' do
  let(:remote_redis) { Redis.new(host: '127.0.0.1', port: '6378') }
  let(:timestamp_formatted) { Time.now.strftime('%Y-%m-%dT%H:%M:%S.%6N ') }
  let(:dump_redis_data) do
    remote_redis
      .keys
      .map { |key| [key.sub('resque_uniqueness_test:', ''), get_redis_data(key)] }
      .to_h
  end

  before do
    remote_redis.del(*remote_redis.keys) if remote_redis.keys.any?
    Resque.redis.del(TestWorker::REDIS_KEY)
  end

  def workers_waiter(*extra_keys)
    while (0..6).any? { have_working_jobs?(*extra_keys) && sleep(0.5) }
      if block_given?
        yield
      else
        sleep(0.5)
      end
    end
  end

  def have_working_jobs?(*extra_keys)
    working_keys = %w[^delayed: ^queue: ^test_worker_performing:] + extra_keys
    working_jobs = /(#{working_keys.join(')|(')})/
    !Resque.redis.keys.grep(working_jobs).empty?
  end

  def scheduled_workers_waiter
    scheduled_keys = %w[delayed: queue:]
    scheduled_jobs = /(#{scheduled_keys.join(')|(')})/
    sleep 1 until Resque.redis.keys.grep(scheduled_jobs).empty?
  end

  def copy_current_redis
    keys_to_migrate = Resque.redis.keys.map { |k| "#{Resque.redis.namespace}:#{k}" }
    Resque.redis.migrate(
      keys_to_migrate,
      host: '127.0.0.1',
      port: '6378',
      copy: true,
      replace: true,
      timeout: 3000
    )
  end

  def get_redis_data(key, redis = remote_redis)
    case redis.type(key).to_sym
    when :string
      redis.get(key)
    when :set
      redis.smembers(key)
    when :hash
      redis.hgetall(key)
    else
      raise NotImplementedError
    end
  end
end
