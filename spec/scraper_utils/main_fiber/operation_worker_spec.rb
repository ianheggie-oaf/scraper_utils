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
    it "closes request queue and joins thread" do
      # Create a real worker with a real queue and thread
      worker = described_class.new(worker_fiber, authority, response_queue)
      request_queue = worker.instance_variable_get(:@request_queue)
      thread = worker.instance_variable_get(:@thread)
      
      # Track if the queue is closed and thread is joined
      original_close = request_queue.method(:close)
      close_called = false
      allow(request_queue).to receive(:close) do
        close_called = true
        original_close.call
      end
      
      original_join = thread.method(:join)
      join_called = false
      allow(thread).to receive(:join) do
        join_called = true
        original_join.call
      end
      
      worker.shutdown
      
      expect(close_called).to be true
      expect(join_called).to be true
      expect(worker.instance_variable_get(:@request_queue)).to be_nil
      expect(worker.instance_variable_get(:@thread)).to be_nil
    end
    
    it "sets resume_at to the future" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      old_resume_at = worker.resume_at
      
      worker.shutdown
      
      expect(worker.resume_at).to be > old_resume_at
    end
    
    it "attempts to resume fiber if it's alive and not the current fiber" do
      alive_fiber = Fiber.new { Fiber.yield }
      worker = described_class.new(alive_fiber, authority, response_queue)
      
      # We need to track if resume was called
      resume_called = false
      original_resume = alive_fiber.method(:resume)
      allow(alive_fiber).to receive(:resume) do |arg|
        resume_called = true
        original_resume.call(arg)
      end
      
      worker.shutdown
      
      expect(resume_called).to be true
    end
    
    it "doesn't resume the current fiber" do
      # Create a class to run a test in a separate fiber
      class CurrentFiberTest
        attr_reader :fiber, :worker, :resume_called
        
        def initialize(authority, response_queue)
          @authority = authority
          @response_queue = response_queue
          @resume_called = false
          @fiber = Fiber.new { self.test }
        end
        
        def test
          # Create a new fiber that we'll use as both current fiber and worker fiber
          current_fiber = Fiber.new { 
            yield # This keeps it alive
          }
          
          # Start the fiber
          current_fiber.resume
          
          # Store current object_id for comparison
          saved_object_id = current_fiber.object_id
          
          # Setup the test - pretend this is the current fiber
          allow(Fiber).to receive(:current).and_return(current_fiber)
          
          # Create worker with this fiber
          @worker = ScraperUtils::Scheduler::OperationWorker.new(
            current_fiber, @authority, @response_queue
          )
          
          # Spy on the resuming
          original_resume = current_fiber.method(:resume)
          allow(current_fiber).to receive(:resume) do |*args|
            @resume_called = true
            original_resume.call(*args)
          end
          
          # Execute the shutdown - this should not try to resume the current fiber
          @worker.shutdown
          
          # Return the test result
          @resume_called
        end
      end
      
      # Run the test
      test = CurrentFiberTest.new(authority, response_queue)
      expect(test.fiber.resume).to eq(false)
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
