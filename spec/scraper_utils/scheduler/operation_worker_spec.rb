# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }
  let(:main_fiber) { ScraperUtils::Scheduler::Constants::MAIN_FIBER }
  let(:worker_fiber) { Fiber.new { :worker_fiber } }

  describe "#initialize" do
    it "creates a valid operation worker" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.fiber).to eq(worker_fiber)
      expect(worker.authority).to eq(authority)
      expect(worker.can_resume?).to be true
      expect(worker.response).to be true
      expect(worker.instance_variable_get(:@request_queue)).to be_a(Thread::Queue)
      expect(worker.instance_variable_get(:@thread)).to be_a(Thread)
    end

    it "raises error if fiber or authority is missing" do
      expect { described_class.new(nil, authority, response_queue) }.to raise_error(ArgumentError)
      expect { described_class.new(worker_fiber, nil, response_queue) }.to raise_error(ArgumentError)
    end
    
    it "sets initial state with resume_at in the future" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.resume_at).to be >= Time.now - 0.1 # Allow small time variance
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
    end
    
    it "creates next resume time with small offset" do
      first_time = described_class.next_resume_at
      second_time = described_class.next_resume_at
      
      expect(second_time - first_time).to be_within(0.0001).of(0.001)
    end
  end
  
  describe "#alive?" do
    it "returns true when fiber is alive" do
      alive_fiber = Fiber.new { Fiber.yield }
      worker = described_class.new(alive_fiber, authority, response_queue)
      
      expect(worker.alive?).to be true
    end
    
    it "returns false when fiber is dead" do
      dead_fiber = Fiber.new { :done }
      dead_fiber.resume # Exhaust the fiber
      worker = described_class.new(dead_fiber, authority, response_queue)
      
      expect(worker.alive?).to be false
    end
  end
  
  describe "#can_resume?" do
    it "returns false if no response is available" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      worker.instance_variable_set(:@response, nil)
      
      expect(worker.can_resume?).to be false
    end
    
    it "returns false if fiber is not alive" do
      dead_fiber = Fiber.new { :done }
      dead_fiber.resume # Exhaust the fiber
      worker = described_class.new(dead_fiber, authority, response_queue)
      
      expect(worker.can_resume?).to be false
    end
    
    it "returns true when response is available and fiber is alive" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.can_resume?).to be true
    end
  end
  
  describe "#save_thread_response" do
    let(:worker) { described_class.new(worker_fiber, authority, response_queue) }
    let(:response) { double("ThreadResponse", delay_till: Time.now + 1, time_taken: 0.5) }
    
    it "raises error if not waiting for response" do
      expect {
        worker.save_thread_response(response)
      }.to raise_error(/Wasn't waiting for response/)
    end
    
    it "saves response and updates state" do
      worker.instance_variable_set(:@waiting_for_response, true)
      
      worker.save_thread_response(response)
      
      expect(worker.response).to eq(response)
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
      expect(worker.resume_at).to be >= Time.now
    end
    
    it "uses current time if delay_till is nil" do
      worker.instance_variable_set(:@waiting_for_response, true)
      allow(response).to receive(:delay_till).and_return(nil)
      
      worker.save_thread_response(response)
      
      expect(worker.resume_at).to be_within(0.1).of(Time.now)
    end
    
    it "returns the response for chaining" do
      worker.instance_variable_set(:@waiting_for_response, true)
      
      expect(worker.save_thread_response(response)).to eq(response)
    end
  end
  
  describe "#shutdown" do
    let(:worker) { described_class.new(worker_fiber, authority, response_queue) }
    
    before do
      # Setup the request queue to be closeable
      @request_queue = worker.instance_variable_get(:@request_queue)
      allow(@request_queue).to receive(:close)
      
      # Setup the thread to be joinable
      @thread = worker.instance_variable_get(:@thread)
      allow(@thread).to receive(:join)
    end
    
    it "closes request queue and sets to nil" do
      worker.shutdown
      
      expect(@request_queue).to have_received(:close)
      expect(worker.instance_variable_get(:@request_queue)).to be_nil
    end
    
    it "joins thread and sets to nil" do
      worker.shutdown
      
      expect(@thread).to have_received(:join)
      expect(worker.instance_variable_get(:@thread)).to be_nil
    end
    
    it "sets resume_at to the future" do
      old_resume_at = worker.resume_at
      
      worker.shutdown
      
      expect(worker.resume_at).to be > old_resume_at
    end
    
    it "attempts to resume fiber if it's alive and not the current fiber" do
      alive_fiber = Fiber.new { Fiber.yield }
      alive_fiber_worker = described_class.new(alive_fiber, authority, response_queue)
      
      # Setup our mocks
      allow(alive_fiber_worker.instance_variable_get(:@request_queue)).to receive(:close)
      allow(alive_fiber_worker.instance_variable_get(:@thread)).to receive(:join)
      allow(alive_fiber).to receive(:resume)
      
      alive_fiber_worker.shutdown
      
      expect(alive_fiber).to have_received(:resume).with(nil)
    end
    
    it "doesn't resume the current fiber" do
      # This test will run in the current fiber, which is already the main fiber
      # We're verifying that we don't try to resume ourselves
      current_fiber_worker = described_class.new(Fiber.current, authority, response_queue)
      
      # Setup our mocks
      allow(current_fiber_worker.instance_variable_get(:@request_queue)).to receive(:close)
      allow(current_fiber_worker.instance_variable_get(:@thread)).to receive(:join)
      allow(Fiber.current).to receive(:resume)
      
      current_fiber_worker.shutdown
      
      expect(Fiber.current).not_to have_received(:resume)
    end
  end
  
  describe "#resume" do
    let(:worker) { described_class.new(worker_fiber, authority, response_queue) }
    
    it "raises error if fiber is not alive" do
      allow(worker).to receive(:alive?).and_return(false)
      
      expect { worker.resume }.to raise_error(ClosedQueueError)
    end
    
    it "raises error if no response is available" do
      worker.instance_variable_set(:@response, nil)
      
      expect { worker.resume }.to raise_error(ScraperUtils::Scheduler::OperationWorker::NotReadyError)
    end
    
    it "resumes fiber with response and returns request" do
      test_request = ScraperUtils::Scheduler::ThreadRequest.new(:test_authority) {
        :test_request
      }
      test_fiber = Fiber.new { |response|
        expect(response).to eq(:test_response)
        test_request
      }
      worker = described_class.new(test_fiber, authority, response_queue)
      worker.instance_variable_set(:@response, :test_response)
      
      request = worker.resume
      
      expect(request).to eq(test_request)
    end
    
    it "submits returned request when non-nil" do
      test_fiber = Fiber.new { |response| :test_request }
      worker = described_class.new(test_fiber, authority, response_queue)
      
      allow(worker).to receive(:submit_request)
      worker.resume
      
      expect(worker).to have_received(:submit_request).with(:test_request)
    end
    
    it "doesn't submit request when nil" do
      test_fiber = Fiber.new { |response| nil }
      worker = described_class.new(test_fiber, authority, response_queue)
      
      allow(worker).to receive(:submit_request)
      worker.resume
      
      expect(worker).not_to have_received(:submit_request)
    end
  end
  
  describe "#submit_request" do
    let(:test_request) { ScraperUtils::Scheduler::ThreadRequest.new(authority) { :test_result } }
    let(:test_response) { instance_double(ScraperUtils::Scheduler::ThreadResponse, delay_till: nil, time_taken: 0.1) }
    
    it "raises error if already waiting for response" do
      # Setup a fiber that yields control to the test
      worker_fiber_instance = Fiber.new do
        # Get initial control
        initial_args = Fiber.yield(:initial_yield)
        
        # Execute the actual test using the passed in block
        test_block = Fiber.yield(:ready_for_block)
        result = test_block.call
        
        # Return control to the test with the result
        Fiber.yield(result)
      end
      
      # Create the worker with our test fiber
      worker = described_class.new(worker_fiber_instance, authority, response_queue)
      
      # Start the fiber
      worker_fiber_instance.resume
      # Give it the initial args (if any)
      worker_fiber_instance.resume(nil)
      
      # Set up the state for the test
      worker.instance_variable_set(:@waiting_for_response, true)
      
      # Run the test and get the result
      result = worker_fiber_instance.resume(-> {
        begin
          worker.submit_request(test_request)
          :no_error
        rescue => e
          e
        end
      })
      
      # Verify the result
      expect(result).to be_a(ScraperUtils::Scheduler::OperationWorker::NotReadyError)
      expect(result.message).to match(/Cannot make a second request/)
    end
    
    it "raises error if request is not a ThreadRequest" do
      # Setup a fiber that will run our test
      worker_fiber_instance = Fiber.new do
        initial_args = Fiber.yield(:initial_yield)
        test_block = Fiber.yield(:ready_for_block)
        result = test_block.call
        Fiber.yield(result)
      end
      
      # Create the worker with our test fiber
      worker = described_class.new(worker_fiber_instance, authority, response_queue)
      
      # Start and prepare fiber
      worker_fiber_instance.resume
      worker_fiber_instance.resume(nil)
      
      # Run the test in the fiber
      result = worker_fiber_instance.resume(-> {
        begin
          worker.submit_request("not a request")
          :no_error
        rescue => e
          e
        end
      })
      
      # Verify the result
      expect(result).to be_a(ArgumentError)
      expect(result.message).to match(/Must be passed a valid ThreadRequest/)
    end
    
    context "with request queue" do
      it "pushes request to queue and yields with true" do
        # Create a testing fiber that will let us control execution
        worker_fiber_instance = Fiber.new do
          worker_var = Fiber.yield(:ready) # First yield to set up
          
          # Second yield runs the actual test block
          test_block = Fiber.yield(:ready_for_block)
          result = test_block.call
          
          # Final yield returns the result to the test
          Fiber.yield(result)
        end
        
        # Create and setup the worker
        worker = described_class.new(worker_fiber_instance, authority, response_queue)
        request_queue = Thread::Queue.new
        worker.instance_variable_set(:@request_queue, request_queue)
        
        # Allow us to track if the queue was used
        allow(request_queue).to receive(:push)
        
        # Start the fiber
        worker_fiber_instance.resume
        worker_fiber_instance.resume(worker)
        
        # Run the test in the fiber context
        worker_fiber_instance.resume(-> {
          # Store the initial state
          initial_waiting = worker.instance_variable_get(:@waiting_for_response)
          
          # Call the method we're testing
          worker.submit_request(test_request)
          
          # Return relevant state for verification
          {
            waiting_before: initial_waiting,
            waiting_after: worker.instance_variable_get(:@waiting_for_response)
          }
        })
        
        # Verify the request was pushed to the queue
        expect(request_queue).to have_received(:push).with(test_request)
      end
    end
    
    context "without request queue (parallel disabled)" do
      it "executes request directly" do
        # Create a testing fiber
        worker_fiber_instance = Fiber.new do
          Fiber.yield(:ready) # First yield to set up
          
          # Second yield runs the test block
          test_block = Fiber.yield(:ready_for_block)
          result = test_block.call
          
          # Return result to test
          Fiber.yield(result)
        end
        
        # Create and setup the worker
        worker = described_class.new(worker_fiber_instance, authority, nil) # nil response_queue disables parallel
        worker.instance_variable_set(:@request_queue, nil)
        
        # Start the fiber
        worker_fiber_instance.resume
        worker_fiber_instance.resume(nil)
        
        # Setup the request to execute
        allow(test_request).to receive(:execute).and_return(test_response)
        
        # Run the test in the fiber context
        result = worker_fiber_instance.resume(-> {
          worker.submit_request(test_request)
        })
        
        # Verify the request was executed directly
        expect(test_request).to have_received(:execute)
        expect(result).to eq(test_response)
      end
    end
  end
end
