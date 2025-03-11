# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }
  let(:main_fiber) { ScraperUtils::Scheduler::Constants::MAIN_FIBER }
  let(:worker_fiber) { Fiber.new { :worker_fiber } }

  describe "#submit_request" do
    # Create a functioning worker fiber that can execute our tests
    let(:worker_fiber_instance) do
      Fiber.new do
        context = Fiber.yield(:ready)  # Initial yield to allow setup
        
        # Allow execution of a block in this fiber's context
        test_block = Fiber.yield(:ready_for_block)
        result = test_block.call
        
        # Return the result to the test
        Fiber.yield(result)
      end
    end
    
    # Create the worker with our test fiber
    let(:worker) do
      worker = described_class.new(worker_fiber_instance, authority, response_queue) 
      worker_fiber_instance.resume # Advance to first yield
      worker_fiber_instance.resume(nil) # Pass nil as context
      worker
    end
    
    let(:request) { instance_double(ScraperUtils::Scheduler::ThreadRequest) }
    
    it "raises error if already waiting for response" do
      # Run the test inside the worker fiber
      result = worker_fiber_instance.resume(-> {
        # Set up test state
        worker.instance_variable_set(:@waiting_for_response, true)
        
        # Execute method under test and capture any exceptions
        begin
          worker.submit_request(request)
          :no_error_raised
        rescue => e
          e
        end
      })
      
      # Verify the exception was raised
      expect(result).to be_a(ScraperUtils::Scheduler::OperationWorker::NotReadyError)
      expect(result.message).to match(/Cannot make a second request/)
    end
    
    it "raises error if request is not a ThreadRequest" do
      # Run the test inside the worker fiber
      result = worker_fiber_instance.resume(-> {
        begin
          worker.submit_request("not a request")
          :no_error_raised
        rescue => e
          e
        end
      })
      
      # Verify the exception was raised
      expect(result).to be_a(ArgumentError)
      expect(result.message).to match(/Must be passed a valid ThreadRequest/)
    end
    
    context "with request queue" do
      before do
        # Set up the request queue for this test context
        worker.instance_variable_set(:@request_queue, Thread::Queue.new)
      end
      
      it "pushes request to queue and yields with true" do
        request_queue = worker.instance_variable_get(:@request_queue)
        
        # Allow us to track queue usage
        allow(request_queue).to receive(:push)
        
        # Run the test in the worker fiber's context
        worker_fiber_instance.resume(-> {
          # Store initial state
          initial_waiting = worker.instance_variable_get(:@waiting_for_response)
          
          # Execute method under test
          worker.submit_request(request)
          
          # Return relevant state for verification
          {
            waiting_before: initial_waiting,
            waiting_after: worker.instance_variable_get(:@waiting_for_response),
            request_pushed: true
          }
        })
        
        # Verify the request was pushed to the queue
        expect(request_queue).to have_received(:push).with(request)
      end
      
      it "raises error if response is nil (shutdown signal)" do
        request_queue = worker.instance_variable_get(:@request_queue)
        
        # Set up for the test
        allow(request_queue).to receive(:push)
        allow(Fiber).to receive(:yield).and_return(nil) # Simulate a shutdown signal
        
        # Run the test in the worker fiber's context
        result = worker_fiber_instance.resume(-> {
          begin
            worker.submit_request(request)
            :no_error_raised
          rescue => e
            e
          end
        })
        
        # Verify appropriate exception was raised for shutdown case
        expect(result).to be_a(RuntimeError)
        expect(result.message).to match(/Terminated fiber/)
      end
    end
    
    context "without request queue (parallel disabled)" do
      before do
        worker.instance_variable_set(:@request_queue, nil)
      end
      
      it "executes request directly" do
        thread_response = instance_double(
          ScraperUtils::Scheduler::ThreadResponse, 
          delay_till: nil, 
          time_taken: 0.1
        )
        
        allow(request).to receive(:execute).and_return(thread_response)
        
        # Run the test in the worker fiber's context
        result = worker_fiber_instance.resume(-> {
          worker.submit_request(request)
        })
        
        # Verify direct execution instead of queuing
        expect(request).to have_received(:execute)
        expect(result).to eq(thread_response)
      end
    end
  end
end
