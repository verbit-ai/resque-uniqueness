# frozen_string_literal: true

namespace :resque do
  namespace :specs do
    desc 'Start multiple Resque workers with recovering system. Should only be used in test mode.'
    task :workers do
      threads = []

      abort 'set COUNT env var, e.g. $ COUNT=2 rake resque:specs:workers' if ENV['COUNT'].to_i < 1

      ENV['COUNT'].to_i.times do
        threads << Thread.new do
          system 'rake resque:work'
        end
      end

      # Checking thread
      Thread.new do
        loop do
          threads.each_with_index do |thread, index|
            next if thread.status

            threads[index] = Thread.new { system 'rake resque:work' }
          end
          sleep 0.2
        end
      end

      threads.each(&:join) while threads.map(&:status).uniq != [false]
    end

    desc 'Start multiple Resque schedulers. Should only be used in test mode.'
    task :scheduler do
      threads = []

      abort 'set COUNT env var, e.g. $ COUNT=2 rake resque:specs:scheduler' if ENV['COUNT'].to_i < 1

      ENV['COUNT'].to_i.times do
        threads << Thread.new do
          system 'rake resque:scheduler'
        end
      end

      threads.each(&:join)
    end
  end
end
