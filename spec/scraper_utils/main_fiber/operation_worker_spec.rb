# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }
  let(:worker_fiber) { Fiber.new { Fiber.yield } } # Use Fiber.yield to keep fiber alive
  
  # Override MAIN_FIBER globally for these tests
  before(:all) do
    @original_main_fiber = ScraperUtils::Scheduler::Constants::MAIN_FIBER
    ScraperUtils::Scheduler::Constants.send(:remove_const, :MAIN_FIBER)
    ScraperUtils::Scheduler::Constants.const_set(:MAIN_FIBER, Fiber.current)
  end
  
  # Restore original MAIN_FIBER after tests
  after(:all) do
    ScraperUtils::Scheduler::Constants.send(:remove_const, :MAIN_FIBER)
    ScraperUtils::Scheduler::Constants.const_set(:MAIN_FIBER, @original_main_fiber)
  end

  describe "#shutdown" do
    it "clears resume state" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      # Set some initial state
      worker.resume_at = Time.now + 10
      worker.response = :some_response
      worker.instance_variable_set(:@waiting_for_response, true)
      
      worker.shutdown
      
      # Verify state is cleared
      expect(worker.resume_at).to be_nil
      expect(worker.response).to be_nil
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
    end
    
    it "resumes fiber with nil if fiber is alive" do
      alive_fiber = Fiber.new { Fiber.yield }
      alive_fiber.resume # Start fiber but leave it alive
      
      worker = described_class.new(alive_fiber, authority, response_queue)
      
      # Check if resume is called with nil
      expect(alive_fiber).to receive(:resume).with(nil)
      
      worker.shutdown
    end
    
    it "doesn't resume the current fiber" do
      # For this test we need to simulate when fiber == Fiber.current
      
      # Create a fiber that will act as both the worker fiber and current fiber
      test_fiber = Fiber.new do
        # Execute code while this is the current fiber
        current_fiber = Fiber.current
        
        # Create a worker with this fiber
        worker = described_class.new(current_fiber, authority, response_queue)
        
        # Track if resume is called
        resume_called = false
        allow(current_fiber).to receive(:resume) do |*args|
          resume_called = true
        end
        
        # Override Fiber.current to return our test fiber
        allow(Fiber).to receive(:current).and_return(current_fiber)
        
        # Call shutdown - this should not try to resume since it's the current fiber
        worker.shutdown
        
        # Return whether resume was called
        resume_called
      end
      
      # Run the test in the test fiber
      result = test_fiber.resume
      
      # Verify resume was not called
      expect(result).to be false
    end
    
    it "raises error if called from worker fiber" do
      # Create a fiber to run the test
      test_fiber = Fiber.new do
        # Create a worker with this fiber
        worker = described_class.new(Fiber.current, authority, response_queue)
        
        # Try to call shutdown from within the fiber
        begin
          worker.shutdown
          "No error raised" # Should not get here
        rescue ArgumentError => e
          e # Return the error
        end
      end
      
      # Run the test
      error = test_fiber.resume
      
      # Verify the error
      expect(error).to be_a(ArgumentError)
      expect(error.message).to match(/Must be run within main fiber/)
    end
  end
  
  describe "#resume" do
    it "raises error if fiber is not alive" do
      dead_fiber = Fiber.new { :done }
      dead_fiber.resume # Exhaust the fiber
      worker = described_class.new(dead_fiber, authority, response_queue)
      
      expect { worker.resume }.to raise_error(ClosedQueueError)
    end
    
    it "raises error if no response is available" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      worker.instance_variable_set(:@response, nil)
      
      expect { worker.resume }.to raise_error(ScraperUtils::Scheduler::OperationWorker::NotReadyError)
    end
    
    it "resumes fiber with response and returns request" do
      test_request = TestThreadRequest.new(authority)
      test_fiber = Fiber.new do |response| 
        expect(response).to eq(:test_response)
        test_request
      end
      
      worker = described_class.new(test_fiber, authority, response_queue)
      worker.instance_variable_set(:@response, :test_response)
      
      # Allow submit_request for proper processing of the returned request
      allow(worker).to receive(:submit_request)
      
      request = worker.resume
      
      expect(request).to eq(test_request)
    end
    
    it "submits returned request when non-nil" do
      test_request = TestThreadRequest.new(authority)
      test_fiber = Fiber.new { |response| test_request }
      worker = described_class.new(test_fiber, authority, response_queue)
      
      # Track if submit_request is called
      expect(worker).to receive(:submit_request).with(test_request)
      
      worker.resume
    end
    
    it "doesn't submit request when nil" do
      test_fiber = Fiber.new { |response| nil }
      worker = described_class.new(test_fiber, authority, response_queue)
      
      # Track that submit_request is not called
      expect(worker).not_to receive(:submit_request)
      
      worker.resume
    end
  end
end
