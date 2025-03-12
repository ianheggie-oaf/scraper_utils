# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }

  # Setup fiber for testing
  let(:fiber) do
    Fiber.new do
      fiber_result = Fiber.yield :ready # First yield to get ready for tests
      Fiber.yield fiber_result # Pass back the result
    end
  end
  
  # Prepare worker with real fiber and thread
  let(:worker) { described_class.new(fiber, authority, response_queue) }

  describe "#submit_request" do
    before do
      # Prepare the fiber for testing
      expect(fiber.resume).to eq(:ready)
    end
    
    it "raises error if already waiting for response" do
      # Set waiting flag to true
      worker.instance_variable_set(:@waiting_for_response, true)
      
      # The worker.submit_request must be executed within fiber's context
      # We'll execute it in the fiber by passing a test code block to the fiber
      expect {
        # Execute inside the fiber's context
        fiber.resume(-> {
          worker.submit_request(TestThreadRequest.new(authority))
        })
      }.to raise_error(ScraperUtils::Scheduler::OperationWorker::NotReadyError, /Cannot make a second request/)
    end
    
    it "raises error if request is not a ThreadRequest" do
      # This also needs to run in the fiber context
      expect {
        fiber.resume(-> {
          worker.submit_request("not a thread request")
        })
      }.to raise_error(ArgumentError, /Must be passed a valid ThreadRequest/)
    end
    
    context "with request queue (parallel processing enabled)" do
      it "processes request through thread and queue" do
        # Create a request
        request = TestThreadRequest.new(authority, result: :test_result)
        
        # The request queue is already created by the worker
        request_queue = worker.instance_variable_get(:@request_queue)
        expect(request_queue).to be_a(Thread::Queue)
        
        # Set up an observer thread to monitor the response_queue
        response_received = false
        response = nil
        
        observer = Thread.new do
          response = response_queue.pop
          response_received = true
        end
        
        # Execute the request in the fiber
        fiber.resume(-> {
          # This pushes to the queue and yields control back to scheduler
          worker.submit_request(request)
        })
        
        # Give the threads time to process
        sleep 0.1
        observer.join(0.1)
        
        # Check that a response was recorded and passed to the response queue
        expect(response_received).to be true
        expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(response.authority).to eq(authority)
        expect(response.result).to eq(:test_result)
        
        # The worker should now be waiting for a response
        expect(worker.instance_variable_get(:@waiting_for_response)).to be true
      end
      
      it "raises error if Fiber.yield returns nil (worker shutdown)" do
        # Create a new fiber that will help us test the shutdown case
        shutdown_fiber = Fiber.new do
          # First yield to get ready
          Fiber.yield(:ready)
          
          # Second yield to execute test
          test_block = Fiber.yield(:ready_for_test)
          
          # Set up Fiber.yield to return nil to simulate shutdown
          original_yield = Fiber.method(:yield)
          
          begin
            # Replace yield to return nil
            Fiber.define_singleton_method(:yield) do |*args|
              nil # Simulate shutdown
            end
            
            # Run the test block
            begin
              test_block.call
              Fiber.yield(:no_error)
            rescue => e
              Fiber.yield(e)
            end
          ensure
            # Restore original yield
            Fiber.define_singleton_method(:yield, original_yield)
          end
        end
        
        # Set up worker with our test fiber
        test_worker = described_class.new(shutdown_fiber, authority, response_queue)
        
        # Start the fiber
        shutdown_fiber.resume
        shutdown_fiber.resume
        
        # Run the test
        result = shutdown_fiber.resume(-> {
          test_worker.submit_request(TestThreadRequest.new(authority))
        })
        
        # Expect the termination error
        expect(result).to be_a(RuntimeError)
        expect(result.message).to match(/Terminated fiber/)
      end
    end
    
    context "without request queue (parallel disabled)" do
      # Create a worker without a response queue to disable parallel processing
      let(:direct_worker) { described_class.new(fiber, authority, nil) }
      
      it "processes request directly without thread" do
        # Create a request
        request = TestThreadRequest.new(authority, result: :direct_result)
        
        # There should be no request queue
        expect(direct_worker.instance_variable_get(:@request_queue)).to be_nil
        
        # Execute the request in the fiber and get result
        result = fiber.resume(-> {
          direct_worker.submit_request(request)
        })
        
        # Verify the request was executed directly
        expect(request.executed).to be true
        expect(result).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(result.result).to eq(:direct_result)
      end
      
      it "handles errors in direct processing" do
        # Create a request that will raise an error
        test_error = RuntimeError.new("Test error")
        request = TestThreadRequest.new(authority, error: test_error)
        
        # Execute the request in the fiber and get result
        result = fiber.resume(-> {
          direct_worker.submit_request(request)
        })
        
        # Verify the error was handled properly
        expect(request.executed).to be true
        expect(result).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(result.error).to eq(test_error)
        expect(result.success?).to be false
      end
      
      it "passes delay_till from request to response" do
        future_time = Time.now + 10
        request = TestThreadRequest.new(authority, delay_till: future_time)
        
        # Execute the request in the fiber and get result
        result = fiber.resume(-> {
          direct_worker.submit_request(request)
        })
        
        # Verify the delay_till was passed from request to response
        expect(result.delay_till).to eq(future_time)
      end
    end
  end

  # Clean up any fibers and threads
  after do
    # Complete any fibers that might still be alive
    if fiber.alive?
      begin
        fiber.resume(nil) while fiber.alive?
      rescue FiberError
        # Ignore errors during cleanup
      end
    end
  end
end
