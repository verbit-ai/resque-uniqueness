# frozen_string_literal: true

RSpec.describe Resque::Plugins::Uniqueness::WorkerExtension do
  let(:worker) { Resque::Worker.new(queue).tap(&:startup) }
  let(:queue) { :test_job }

  describe '#working_on', :with_recovering_queue_helper, :with_resque_worker_helepr do
    subject(:call) { worker.working_on(job) }

    let(:job) { Resque::Job.new(queue, item.transform_keys(&:to_s)) }
    let(:item) { {class: 'UntilExecutingWorker', args: ['test'], recovering_uuid: 12} }

    its_block {
      is_expected.to change(&method(:worker_processing_jobs))
        .from([])
        .to([hash_including(queue: queue.to_s, payload: item)])
    }
    its_block { is_expected.not_to change(&method(:items_in_recovering_queue)) }

    context 'when item in the recovering queue' do
      before { push_to_recovering_queue(item) }

      its_block {
        is_expected.to change(&method(:worker_processing_jobs))
          .from([])
          .to([hash_including(queue: queue.to_s, payload: item)])
      }
      its_block {
        is_expected.to change(&method(:items_in_recovering_queue))
          .from([array_including(hash_including(item))])
          .to([])
      }
    end
  end
end
