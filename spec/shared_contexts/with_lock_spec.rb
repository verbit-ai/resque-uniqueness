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

  def stub_locked_on_execute
    allow(lock_instance).to receive(:locked_on_execute?) do
      args_include?('locked_on_execute')
    end
  end

  def stub_locked_on_schedule
    allow(lock_instance).to receive(:locked_on_schedule?) do
      args_include?('locked_on_schedule')
    end
  end

  def stub_unlock_schedule
    allow(lock_instance).to receive(:unlock_schedule)
  end

  def stub_unlock_execute
    allow(lock_instance).to receive(:unlock_execute)
  end

  def stub_should_lock_on_schedule
    allow(lock_instance).to receive(:should_lock_on_schedule?) do
      args_include?('should_lock_on_schedule')
    end
  end

  def stub_should_lock_on_execute
    allow(lock_instance).to receive(:should_lock_on_execute?) do
      args_include?('should_lock_on_execute')
    end
  end

  def args_include?(argument)
    lock_instance.instance_variable_get(:@job).payload['args'].include?(argument)
  end

  def stub_lock_schedule
    allow(lock_instance).to receive(:lock_schedule)
  end

  def stub_lock_execute
    allow(lock_instance).to receive(:lock_execute)
  end
end
