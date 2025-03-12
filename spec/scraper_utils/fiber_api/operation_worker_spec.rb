# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }

  describe "#submit_request" do
    it "raises error if already waiting for response" do
      # Create a fiber for this test
      fiber = Fiber.new do |action|
        action.is_a?(Proc) ? action.call : action
      end

      worker = described_class.new(fiber, authority, response_queue)
      worker.instance_variable_set(:@waiting_for_response, true)

      expect { fiber.resume(-> {
        worker.submit_request(TestThreadRequest.new(authority))
      }) }
        .to raise_error(ScraperUtils::Scheduler::OperationWorker::NotReadyError, /Cannot make a second request/)
    end

    it "raises error if request is not a ThreadRequest" do
      fiber = Fiber.new do |action|
        action.is_a?(Proc) ? action.call : action
      end

      worker = described_class.new(fiber, authority, response_queue)

      expect { fiber.resume(-> {
        worker.submit_request("not a thread request")
      }) }
        .to raise_error(ArgumentError, /Must be passed a valid ThreadRequest/)
    end

    context "with request queue (parallel processing enabled)" do
      it "processes request through thread and queue" do
        fiber = Fiber.new do |action|
          action.is_a?(Proc) ? action.call : action
        end

        worker = described_class.new(fiber, authority, response_queue)
        request = TestThreadRequest.new(authority, result: :test_result)

        # Start a thread to capture the response
        thread = Thread.new do
          response_queue.pop
        end

        # Run in fiber context
        fiber.resume(-> {
          worker.submit_request(request)
        })

        # Get the response from our thread
        response = thread.value

        expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(response.authority).to eq(authority)
        expect(response.result).to eq(:test_result)
        expect(response.error).to be_nil
        expect(worker.instance_variable_get(:@waiting_for_response)).to be true
      end

      it "raises error if Fiber.yield returns nil (worker shutdown)" do
        # Let's use a real Fiber that will override Fiber.yield briefly
        original_yield = Fiber.method(:yield)
        begin
          # Override Fiber.yield to return nil for our test
          Fiber.define_singleton_method(:yield) do |*args|
            nil # This simulates a shutdown
          end
          
          # Create a test fiber that will actually execute our worker test
          test_fiber = Fiber.new do
            # Inside this fiber, Fiber.yield will return nil due to our override
            test_worker = ScraperUtils::Scheduler::OperationWorker.new(
              Fiber.current, authority, response_queue
            )
            
            # This should raise the error we're testing for
            begin
              test_worker.submit_request(TestThreadRequest.new(authority))
              "Did not raise error" # Should not reach here
            rescue RuntimeError => e
              e # Return the error to check it
            end
          end
          
          # Get the result from our test
          result = test_fiber.resume
          
          # Verify we got the expected error
          expect(result).to be_a(RuntimeError)
          expect(result.message).to match(/Terminated fiber/)
        ensure
          # Always restore original Fiber.yield
          Fiber.singleton_class.send(:remove_method, :yield)
          Fiber.define_singleton_method(:yield, original_yield)
        end
      end
    end

    context "without request queue (parallel disabled)" do
      it "processes request directly without thread" do
        fiber = Fiber.new do |action|
          action.is_a?(Proc) ? action.call : action
        end

        worker = described_class.new(fiber, authority, nil)
        request = TestThreadRequest.new(authority, result: :direct_result)

        result = fiber.resume(-> {
          worker.submit_request(request)
        })

        expect(request.executed).to be true
        expect(result).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(result.result).to eq(:direct_result)
        expect(result.error).to be_nil
      end

      it "handles errors in direct processing" do
        fiber = Fiber.new do |action|
          action.is_a?(Proc) ? action.call : action
        end

        worker = described_class.new(fiber, authority, nil)
        test_error = RuntimeError.new("Test error")
        request = TestThreadRequest.new(authority, error: test_error)

        result = fiber.resume(-> {
          worker.submit_request(request)
        })

        expect(request.executed).to be true
        expect(result).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(result.error).to eq(test_error)
        expect(result.success?).to be false
      end

      it "passes delay_till from request to response" do
        fiber = Fiber.new do |action|
          action.is_a?(Proc) ? action.call : action
        end

        worker = described_class.new(fiber, authority, nil)
        future_time = Time.now + 10
        request = TestThreadRequest.new(authority, delay_till: future_time)

        result = fiber.resume(-> {
          worker.submit_request(request)
        })

        expect(result.delay_till).to eq(future_time)
      end
    end
  end
end
