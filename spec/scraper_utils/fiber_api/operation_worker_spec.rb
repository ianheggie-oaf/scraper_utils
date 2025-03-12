# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }
  let(:main_fiber) { ScraperUtils::Scheduler::Constants::MAIN_FIBER }

  # Create a more elaborate fiber that can capture test contexts
  def create_test_fiber
    Fiber.new do
      # First yield to set up test
      setup_data = Fiber.yield(:ready_for_setup)
      
      # Second yield to run actual test
      test_block = Fiber.yield(:ready_for_test)
      
      # Run the test in this fiber's context
      result = test_block.call(setup_data)
      
      # Return result to test runner
      Fiber.yield(result)
    end
  end

  describe "#submit_request" do
    let(:test_fiber) { create_test_fiber }
    let(:request) { ScraperUtils::Scheduler::ThreadRequest.new(authority) { 42 } }
    
    # Helper method to run a test in the worker fiber's context
    def run_in_fiber(worker, test_block)
      # Start the fiber
      test_fiber.resume
      # Pass setup data
      test_fiber.resume(worker)
      # Run the test block
      test_fiber.resume(test_block)
    end
    
    it "raises error if already waiting for response" do
      worker = described_class.new(test_fiber, authority, response_queue)
      
      result = run_in_fiber(worker, lambda { |w|
        # Setup test state
        w.instance_variable_set(:@waiting_for_response, true)
        
        # Execute method under test and capture any exceptions
        begin
          w.submit_request(request)
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
      worker = described_class.new(test_fiber, authority, response_queue)
      
      result = run_in_fiber(worker, lambda { |w|
        begin
          w.submit_request("not a request")
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
      let(:request_queue) { Thread::Queue.new }
      
      it "pushes request to queue and yields with true" do
        worker = described_class.new(test_fiber, authority, response_queue)
        worker.instance_variable_set(:@request_queue, request_queue)
        
        # Allow us to track queue usage
        allow(request_queue).to receive(:push)
        
        # Run test in fiber context
        run_in_fiber(worker, lambda { |w|
          # Execute method and capture calls to Fiber.yield
          allow(Fiber).to receive(:yield).and_call_original
          allow(Fiber).to receive(:yield).with(true).and_return(:fake_response)
          
          # Call the method
          result = w.submit_request(request)
          
          # Return tracking data
          {
            yield_called: Fiber.yield == :fake_response,
            request_pushed: true,
            result: result
          }
        })
        
        # Verify the request was pushed to the queue
        expect(request_queue).to have_received(:push).with(request)
      end
      
      it "raises error if response is nil (shutdown signal)" do
        worker = described_class.new(test_fiber, authority, response_queue)
        worker.instance_variable_set(:@request_queue, request_queue)
        
        result = run_in_fiber(worker, lambda { |w|
          # Setup Fiber.yield to return nil (shutdown signal)
          allow(Fiber).to receive(:yield).and_return(nil)
          
          # Execute method and capture any exceptions
          begin
            w.submit_request(request)
            :no_error_raised
          rescue => e
            e
          end
        })
        
        # Verify the exception was raised
        expect(result).to be_a(RuntimeError)
        expect(result.message).to match(/Terminated fiber/)
      end
    end
    
    context "without request queue (parallel disabled)" do
      let(:thread_response) { instance_double(
        ScraperUtils::Scheduler::ThreadResponse,
        delay_till: nil,
        time_taken: 0.1
      )}
      
      it "executes request directly" do
        worker = described_class.new(test_fiber, authority, nil)
        worker.instance_variable_set(:@request_queue, nil)
        
        # Setup the request to execute and return a response
        allow(request).to receive(:execute).and_return(thread_response)
        
        # Run test in fiber context
        result = run_in_fiber(worker, lambda { |w|
          # Call the method
          response = w.submit_request(request)
          
          # Return result for verification
          response
        })
        
        # Verify the request was executed directly
        expect(request).to have_received(:execute)
        expect(result).to eq(thread_response)
      end
    end
  end
end
