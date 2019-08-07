# frozen_string_literal: true

RSpec.shared_context 'with lock' do |*stubbed_methods|
  let(:lock_instance) { instance_double(lock_class) }

  before do
    stubbed_methods.each { |stub_method| public_send("stub_#{stub_method}") }

    allow(lock_class).to receive(:new) do |job|
      lock_instance.instance_variable_set(:@job, job)
      lock_instance
    end
  end

  def stub_perform_locked
    allow(lock_instance).to receive(:perform_locked?) do
      args_include?('perform_locked')
    end
  end

  def stub_queueing_locked
    allow(lock_instance).to receive(:queueing_locked?) do
      args_include?('queueing_locked')
    end
  end

  def stub_ensure_unlock_queueing
    allow(lock_instance).to receive(:ensure_unlock_queueing)
  end

  def stub_ensure_unlock_perform
    allow(lock_instance).to receive(:ensure_unlock_perform)
  end

  def args_include?(argument)
    lock_instance.instance_variable_get(:@job).payload['args'].include?(argument)
  end

  def stub_try_lock_queueing
    allow(lock_instance).to receive(:try_lock_queueing)
  end

  def stub_try_lock_perform
    allow(lock_instance).to receive(:try_lock_perform)
  end
end
