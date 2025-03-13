# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationRegistry do
  let(:response_queue) { Thread::Queue.new }
  let(:registry) { described_class.new }
  let(:authority1) { :authority1 }
  let(:authority2) { :authority2 }
  let(:fiber1) { Fiber.new { :fiber1 } }
  let(:fiber2) { Fiber.new { :fiber2 } }

  describe "#initialize" do
    it "creates empty operations and fiber_ids hashes" do
      expect(registry.instance_variable_get(:@operations)).to eq({})
      expect(registry.instance_variable_get(:@fiber_ids)).to eq({})
    end
  end

  describe "#register and #deregister" do
    it "registers and deregisters operations" do
      fiber = Fiber.new { :test_fiber }
      
      # Register the operation
      registry.instance_variable_set(:@response_queue, response_queue)
      registry.register(fiber, authority1)
      
      # Verify it was registered
      operations = registry.instance_variable_get(:@operations)
      fiber_ids = registry.instance_variable_get(:@fiber_ids)
      
      expect(operations[authority1]).to be_a(ScraperUtils::Scheduler::OperationWorker)
      expect(fiber_ids[fiber.object_id]).to eq(operations[authority1])
      
      # Deregister the operation
      registry.deregister(authority1)
      
      # Verify it was deregistered
      expect(registry.instance_variable_get(:@operations)).to be_empty
      expect(registry.instance_variable_get(:@fiber_ids)).to be_empty
    end
  end
  
  describe "#find and #current_authority" do
    let(:operation) { double("OperationWorker", fiber: Fiber.current, authority: authority1) }
    
    before do
      registry.instance_variable_set(:@operations, { authority1 => operation })
      registry.instance_variable_set(:@fiber_ids, { Fiber.current.object_id => operation })
    end
    
    it "finds operations by various keys" do
      expect(registry.find(authority1)).to eq(operation)
      expect(registry.find(Fiber.current.object_id)).to eq(operation)
      expect(registry.find).to eq(operation)
      expect(registry.current_authority).to eq(authority1)
    end
  end
  
  describe "#can_resume and #process_thread_response" do
    let(:operation) { 
      double("OperationWorker", 
             authority: authority1,
             can_resume?: true, 
             resume_at: Time.now,
             save_thread_response: nil)
    }
    
    before do
      registry.instance_variable_set(:@operations, { authority1 => operation })
    end
    
    it "handles resumable operations" do
      expect(registry.can_resume).to eq([operation])
      
      response = double("ThreadResponse", authority: authority1)
      registry.process_thread_response(response)
      
      expect(operation).to have_received(:save_thread_response).with(response)
    end
  end
  
  describe "#shutdown, #empty? and #size" do
    it "manages the registry state" do
      expect(registry.empty?).to be true
      expect(registry.size).to eq(0)
      
      # Add some operations
      registry.instance_variable_set(:@operations, { 
        authority1 => double("Op1", close: nil), 
        authority2 => double("Op2", close: nil) 
      })
      
      expect(registry.empty?).to be false
      expect(registry.size).to eq(2)
      
      # Shut down
      registry.shutdown
      
      expect(registry.empty?).to be true
      expect(registry.size).to eq(0)
    end
  end
end
