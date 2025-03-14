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
        result1 = nil
        result2 = nil
        worker = ScraperUtils::Scheduler.register_operation(:test_operation) do
          puts 'AAA'
          result1 = ScraperUtils::Scheduler.execute_request('first', :succ, [])
          puts 'BBB'
          result2 = ScraperUtils::Scheduler.execute_request('second', :succ, [])
          puts 'CCC'
        end

        # Start the fiber - it will yield during submit_request
        response = worker.fiber.resume nil
        expect(response).to be :first_yield

        # Now resume with nil to simulate shutdown
        error = test_fiber.resume(nil)

        # Verify the error
        expect(error).to be_a(RuntimeError)
        expect(error.message).to match(/Terminated fiber for #{authority} as requested/)
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

  describe "#close" do
    it "cleans up thread resources when aborted" do
      # Create a fiber we'll use as the worker fiber
      executed = false
      worker = ScraperUtils::Scheduler.register_operation(:test_operation) do
        executed = 1
        ScraperUtils::Scheduler.execute_request('aa', :succ, [])
        executed = 2
      end

      # Verify state for active worker
      expect(worker.instance_variable_get(:@request_queue)).to be_a Thread::Queue
      expect(worker.instance_variable_get(:@thread)).to be_a Thread
      expect(worker.instance_variable_get(:@resume_at)).to be_a Time
      expect(worker.instance_variable_get(:@response)).to be_nil
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false

      # Prepare the request queue and thread for tests
      request_queue = worker.instance_variable_get(:@request_queue)
      thread = worker.instance_variable_get(:@thread)

      # Track if methods are called
      allow(request_queue).to receive(:close).and_call_original
      allow(thread).to receive(:join).and_call_original

      # Start the fiber running
      request = worker_fiber.resume(:start)
      puts "REQUEST: #{request.inspect}"

      expect(worker.instance_variable_get(:@response)).to be_nil
      expect(worker.instance_variable_get(:@waiting_for_response)).to be true

      # Abort
      worker_fiber.resume(nil)

      # These will be called from inside the fiber
      expect(request_queue).to have_received(:close)
      expect(thread).to have_received(:join)

      # Verify state is cleared
      expect(worker.instance_variable_get(:@request_queue)).to be_nil
      expect(worker.instance_variable_get(:@thread)).to be_nil
      expect(worker.instance_variable_get(:@resume_at)).to be_nil
      expect(worker.instance_variable_get(:@response)).to be_nil
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
    end

    it "raises error if called from main fiber" do
      fiber = Fiber.new { Fiber.yield }
      fiber.resume # Start the fiber

      worker = described_class.new(fiber, authority, response_queue)

      # Call close from main fiber - this should raise an error
      expect { worker.close }.to raise_error(ArgumentError, /Must be run within own fiber/)
    end
  end
end
