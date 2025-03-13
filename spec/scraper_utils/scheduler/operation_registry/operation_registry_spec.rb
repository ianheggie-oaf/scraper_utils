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

  describe "#deregister" do
    let(:operation) { double("OperationWorker", 
                             fiber: fiber1, 
                             authority: authority1,
                             close: nil) }
    
    before do
      registry.instance_variable_set(:@operations, { authority1 => operation })
      registry.instance_variable_set(:@fiber_ids, { fiber1.object_id => operation })
    end
    
    it "shuts down and removes operation by authority key" do
      registry.deregister(authority1)
      
      expect(operation).to have_received(:close)
      expect(registry.instance_variable_get(:@operations)).to be_empty
      expect(registry.instance_variable_get(:@fiber_ids)).to be_empty
    end
    
    it "shuts down and removes operation by fiber ID key" do
      registry.deregister(fiber1.object_id)
      
      expect(operation).to have_received(:close)
      expect(registry.instance_variable_get(:@operations)).to be_empty
      expect(registry.instance_variable_get(:@fiber_ids)).to be_empty
    end
    
    it "does nothing if the key is not found" do
      registry.deregister(:unknown_key)
      
      expect(operation).not_to have_received(:close)
      expect(registry.instance_variable_get(:@operations)).not_to be_empty
      expect(registry.instance_variable_get(:@fiber_ids)).not_to be_empty
    end
  end
end
