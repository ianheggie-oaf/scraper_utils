# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationRegistry do
  let(:response_queue) { Thread::Queue.new }
  let(:registry) { described_class.new }
  let(:authority1) { :authority1 }
  let(:authority2) { :authority2 }
  let(:authority3) { :authority3 }
  let(:fiber1) { Fiber.new { :fiber1 } }
  let(:fiber2) { Fiber.new { :fiber2 } }

  describe "#initialize" do
    it "creates empty operations and fiber_ids hashes" do
      expect(registry.instance_variable_get(:@operations)).to eq({})
      expect(registry.instance_variable_get(:@fiber_ids)).to eq({})
    end
  end

  describe "#register" do
    it "creates an OperationWorker and registers it by authority and fiber ID" do
      fiber = Fiber.new { :test_fiber }
      
      operation = double("OperationWorker", 
                         fiber: fiber, 
                         authority: authority1)
                         
      allow(ScraperUtils::Scheduler::OperationWorker).to receive(:new)
        .with(fiber, authority1, response_queue)
        .and_return(operation)
        
      # Call before setting expectation on object_id to avoid capturing the expectation setup call
      fiber_id = fiber.object_id
      
      registry.instance_variable_set(:@response_queue, response_queue)
      registry.register(fiber, authority1)
      
      operations = registry.instance_variable_get(:@operations)
      fiber_ids = registry.instance_variable_get(:@fiber_ids)
      
      expect(operations[authority1]).to eq(operation)
      expect(fiber_ids[fiber_id]).to eq(operation)
      expect(ScraperUtils::Scheduler::OperationWorker).to have_received(:new)
        .with(fiber, authority1, response_queue)
    end
  end
end
